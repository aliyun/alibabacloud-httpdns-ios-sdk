//
//  HttpdnsIpStackDetector.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/16.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsIpStackDetector.h"
#import "HttpdnsLog_Internal.h"
#include <strings.h>
#include <errno.h>
#include <endian.h>
#include <unistd.h>
#include <netinet/in.h>
#include <sys/socket.h>

typedef union httpdns_sockaddr_union {
    struct sockaddr httpdns_generic;
    struct sockaddr_in httpdns_in;
    struct sockaddr_in6 httpdns_in6;
} httpdns_sockaddr_union;

/*
 * 连接UDP套接字到指定的单播地址。这不会产生网络流量，
 * 但如果系统对目标没有或有限的可达性（例如，没有IPv4地址，没有IPv6默认路由等），
 * 将快速失败。
 */
static const unsigned int kMaxLoopCount = 10;

static int httpdns_test_connect(int pf, struct sockaddr * addr, size_t addrlen) {
    int s = socket(pf, SOCK_DGRAM, IPPROTO_UDP);
    if (s < 0) {
        return 0;
    }
    int ret;
    unsigned int loop_count = 0;
    do {
        ret = connect(s, addr, (socklen_t)addrlen);
    } while (ret < 0 && errno == EINTR && loop_count++ < kMaxLoopCount);
    if (loop_count >= kMaxLoopCount) {
        HttpdnsLogDebug("connect error. loop_count = %d", loop_count);
    }
    int success = (ret == 0);
    loop_count = 0;
    do {
        ret = close(s);
    } while (ret < 0 && errno == EINTR && loop_count++ < kMaxLoopCount);
    if (loop_count >= kMaxLoopCount) {
        HttpdnsLogDebug("close error. loop_count = %d", loop_count);
    }
    return success;
}

/*
 * 以下函数用于确定IPv4或IPv6连接是否可用，以实现AI_ADDRCONFIG。
 *
 * 严格来说，AI_ADDRCONFIG不应该检查连接是否可用，
 * 而是检查指定协议族的地址是否"在本地系统上配置"。
 * 然而，bionic目前不支持getifaddrs，
 * 所以检查连接是下一个最佳选择。
 */
static int httpdns_have_ipv6(void) {
    static struct sockaddr_in6 sin6_test = {0};
    sin6_test.sin6_family = AF_INET6;
    sin6_test.sin6_port = 80;
    sin6_test.sin6_flowinfo = 0;
    sin6_test.sin6_scope_id = 0;
    bzero(sin6_test.sin6_addr.s6_addr, sizeof(sin6_test.sin6_addr.s6_addr));
    sin6_test.sin6_addr.s6_addr[0] = 0x20;
    // union
    httpdns_sockaddr_union addr = {.httpdns_in6 = sin6_test};
    return httpdns_test_connect(PF_INET6, &addr.httpdns_generic, sizeof(addr.httpdns_in6));
}

static int httpdns_have_ipv4(void) {
    static struct sockaddr_in sin_test = {0};
    sin_test.sin_family = AF_INET;
    sin_test.sin_port = 80;
    sin_test.sin_addr.s_addr = htonl(0x08080808L);  // 8.8.8.8
    // union
    httpdns_sockaddr_union addr = {.httpdns_in = sin_test};
    return httpdns_test_connect(PF_INET, &addr.httpdns_generic, sizeof(addr.httpdns_in));
}

/**
 * 基于IPv4和IPv6连接检测当前IP协议栈类型
 */
static HttpdnsIPStackType detectIpStack(void) {
    int hasIPv4 = httpdns_have_ipv4();
    int hasIPv6 = httpdns_have_ipv6();

    HttpdnsLogDebug("IP stack detection: IPv4=%d, IPv6=%d", hasIPv4, hasIPv6);

    if (hasIPv4 && hasIPv6) {
        return kHttpdnsIpDual;
    } else if (hasIPv4) {
        return kHttpdnsIpv4Only;
    } else if (hasIPv6) {
        return kHttpdnsIpv6Only;
    } else {
        return kHttpdnsIpUnknown;
    }
}

@implementation HttpdnsIpStackDetector {
    HttpdnsIPStackType _lastDetectedIpStack;
    dispatch_queue_t _detectSerialQueue; // 用于控制检测操作的串行队列
    BOOL _isDetecting;                   // 标记是否正在进行检测
}

+ (instancetype)sharedInstance {
    static HttpdnsIpStackDetector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastDetectedIpStack = kHttpdnsIpUnknown;
        _isDetecting = NO;
        // 创建串行队列用于控制IP栈检测的并发
        _detectSerialQueue = dispatch_queue_create("com.aliyun.httpdns.ipstack.detect", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (HttpdnsIPStackType)currentIpStack {
    // 如果当前已经在主队列，直接返回值
    if (NSThread.isMainThread) {
        return _lastDetectedIpStack;
    }

    // 如果不在主队列，同步获取主队列中的值以确保线程安全
    __block HttpdnsIPStackType result;
    dispatch_sync(dispatch_get_main_queue(), ^{
        result = self->_lastDetectedIpStack;
    });
    return result;
}

- (BOOL)isIpv6OnlyNetwork {
    return [self currentIpStack] == kHttpdnsIpv6Only;
}

- (HttpdnsIPStackType)redetectIpStack {
    // 完全异步执行，将检查逻辑放在串行队列中
    dispatch_async(_detectSerialQueue, ^{
        // 如果已经在检测中，直接返回
        if (self->_isDetecting) {
            HttpdnsLogDebug("IP stack detection already in progress, skipping");
            return;
        }

        // 标记为正在检测并执行检测
        self->_isDetecting = YES;

        // 执行实际的检测操作（已经在串行队列中，无需再次异步）
        HttpdnsIPStackType detectedStack = detectIpStack();

        // 在主队列中更新结果，确保线程安全
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_lastDetectedIpStack = detectedStack;
            HttpdnsLogDebug("IP stack redetection completed: %d", detectedStack);

            // 重置检测状态（已经在串行队列的异步块中，完成后再次异步到串行队列）
            dispatch_async(self->_detectSerialQueue, ^{
                self->_isDetecting = NO;
            });
        });
    });

    // 立即返回当前值，异步更新后的值将在下次调用currentIpStack时返回
    return [self currentIpStack];
}

@end
