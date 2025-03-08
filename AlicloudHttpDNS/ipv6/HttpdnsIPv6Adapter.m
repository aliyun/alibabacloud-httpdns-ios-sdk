//
//  AlicloudIPv6Adapter.m
//  AlicloudUtils
//
//  Created by lingkun on 16/5/16.
//  Copyright © 2016年 Ali. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <arpa/inet.h>
#include <dns.h>
#include <err.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <resolv.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>

#import "HttpdnsIPv6PrefixResolver.h"
#import "HttpdnsIPv6Adapter.h"
#import "HttpdnsRoute.h"

#import "HttpdnsGetgateway.h"
#import "HttpdnsSocketUdp.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsUtil.h"

#define UNKNOWN_STACK         0
#define SUPPORT_IPV4_STACK    1
#define SUPPORT_IPV6_STACK    2
#define ROUNDUP_LEN(a) \
((a) > 0 ? (1 + (((a) - 1) | (sizeof(long) - 1))) : sizeof(long))
#define TypeEN    "en0"

#define IOS_9_VERSION     @"9.0"

#define ALICLOUD_UTILS_IPV6HELP_MAX_DETECT_TIMES     20
#define ALICLOUD_UTILS_IPV6HELP_DETECT_INTERVAL      5


@interface HttpdnsIPv6Adapter ()

@property (nonatomic, strong)   dispatch_queue_t    ipStackDetectingQueue;   // 同步，防止多线程同时触发
@property (nonatomic, assign)   AlicloudIPStackType       ipStackType;
@property (nonatomic, strong)   NSTimer             *timer;
@property (atomic, assign)      NSUInteger          detectedTimes;


@end


@implementation HttpdnsIPv6Adapter

- (instancetype)init {
    if (self = [super init]) {

        _ipStackDetectingQueue  = dispatch_queue_create("utils.httpdns.ipstackdetecting.queue", DISPATCH_QUEUE_SERIAL);
        _ipStackType            = kAlicloudIPUnkown;
        _detectedTimes          = 0;

    }
    return self;
}

+ (BOOL)deviceSystemIsLargeIOS9 {
    static BOOL __ios9__ = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __ios9__ = [[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0;
    });

    return __ios9__;
}

+ (instancetype)getInstance {
    static id singletonInstance = nil;
    static dispatch_once_t once_token;
    dispatch_once(&once_token, ^{
        if (!singletonInstance) {
            singletonInstance = [[super allocWithZone:NULL] init];
        }
    });
    return singletonInstance;
}

+ (id)allocWithZone:(struct _NSZone *)zone {
    return [self getInstance];
}

- (id)copyWithZone:(struct _NSZone *)zone {
    return self;
}

- (BOOL)isIPv6OnlyNetwork {
    if (self.ipStackType != kAlicloudIPUnkown) {
        return (self.ipStackType == kAlicloudIPv6only);
    }

    self.ipStackType = [self currentIpStackType];
    return (self.ipStackType == kAlicloudIPv6only);
}


- (BOOL)reResolveIPv6OnlyStatus {
    [self reset];
    return [self isIPv6OnlyNetwork];
}

- (NSString *)handleIpv4Address:(NSString *)addr {
    if (!addr || ![self isIPv4Address:addr]) {
        return addr;
    }

    NSString *convertedAddr;
    if ([self isIPv6OnlyNetwork]) {
        HttpdnsLogDebug("[AliCloudIPv6Adapter]: In IPv6-Only network status, convert IP address.");
        convertedAddr = [[HttpdnsIPv6PrefixResolver getInstance] convertIPv4toIPv6:addr];
    } else  {
        HttpdnsLogDebug("[AliCloudIPv6Adapter]: Not in IPv6-Only network status, return.");
        convertedAddr = addr;
    }

    // return valid addr
    if ([self isIPv4Address:convertedAddr] || [self isIPv6Address:convertedAddr]) {
        return convertedAddr;
    }
    return addr;
}

/**
 *  判断是否为IPv4地址
 */
- (BOOL)isIPv4Address:(NSString *)addr {
    if (!addr) {
        return NO;
    }
    const char *utf8 = [addr UTF8String];
    // Check valid IPv4.
    struct in_addr dst;
    int success = inet_pton(AF_INET, utf8, &(dst.s_addr));
    return (success == 1);
}

/**
 *  判断是否为IPv6地址
 */
- (BOOL)isIPv6Address:(NSString *)addr {
    if (!addr) {
        return NO;
    }
    const char *utf8 = [addr UTF8String];
    // Check valid IPv6.
    struct in6_addr dst6;
    int success = inet_pton(AF_INET6, utf8, &dst6);
    return (success == 1);
}


- (AlicloudIPStackType)currentIpStackType {
    AlicloudIPStackType type = self.ipStackType;
    if (type != kAlicloudIPUnkown) {
        return type;
    }

    // 同步探测，但是放在同一个同步队列里
    dispatch_sync(self.ipStackDetectingQueue, ^(){
        // 双重判断，避免重复探测
        if (self.ipStackType == kAlicloudIPUnkown) {
            HttpdnsLogDebug("[AlicloudUtil-IPV6Help] Start detecting network stack type, current detect time: %ld", self.detectedTimes);

            // 先检查一次
            self.ipStackType = [self detectIpStack];

            // 注意：因为双栈情况下v4 ip 与 v6 ip 分配有先后，且时间不定，所以需要间隔一段时间后再查询一遍
            // 最大重复次数：20次
            if (self.ipStackType != kAlicloudIPdual && self.detectedTimes == 0) {
                [self timerinvalidate];
                self.timer = [NSTimer scheduledTimerWithTimeInterval:ALICLOUD_UTILS_IPV6HELP_DETECT_INTERVAL target:self selector:@selector(redetect) userInfo:nil repeats:YES];
            }
        }
    });

    return self.ipStackType;
}

- (void)reset {
    HttpdnsLogDebug("[AlicloudUtil-IPV6Help] reset...");

    dispatch_sync(self.ipStackDetectingQueue, ^(){
        [self timerinvalidate];
        self.detectedTimes = 0;

        self.ipStackType = kAlicloudIPUnkown;
    });

}


#pragma mark - private

- (void)timerinvalidate {
    if (_timer) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (AlicloudIPStackType)detectIpStack {
    char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];

    // S0: 先获取IPv6 gateway: 没有IPv6网关，认为是IPv4-only网络
    struct in6_addr addr6;
    if (-1 == getdefaultgateway6(&addr6)) {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] [IPv6-Test] detect IP stack type: IPv4-only");
        return kAlicloudIPv4only;
    }
    if (inet_ntop(AF_INET6, &addr6, addrBuf, INET6_ADDRSTRLEN)) {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] IPv6 gateway: %@", [NSString stringWithUTF8String:addrBuf]);
    }

    // S1: 获取IPv4 gateway: 没有IPv4网关，认为是IPv6-only网络
    struct in_addr addr4;
    if (-1 == getdefaultgateway(&addr4)) {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] [IPv6-Test] detect IP stack type: IPv6-only");
        return kAlicloudIPv6only;
    }
    if (inet_ntop(AF_INET, &addr4, addrBuf, INET_ADDRSTRLEN)) {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] IPv4 gateway: %@", [NSString stringWithUTF8String:addrBuf]);
    }

    // S2: UDP 探测
    AlicloudIPStackType ipstackType = kAlicloudIPUnkown;
    if ( test_udp_connect_ipv4() ) {
        ipstackType |= kAlicloudIPv4only;
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] IPv4 UDP connect success");
    }
    if ( test_udp_connect_ipv6() ) {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] IPv6 UDP connect success");
        ipstackType |= kAlicloudIPv6only;
    }

    // S3: 在 iOS 版本<9.0 的情况下，如果是双栈，需要进一步通过 DNS 判断
    if (ipstackType == kAlicloudIPdual && ![HttpdnsIPv6Adapter deviceSystemIsLargeIOS9] ) {
        ipstackType = [self currentDnsIPStackType];
    }

    if (ipstackType == kAlicloudIPdual) {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] [IPv6-Test] detect IP stack type: Dual-Stack");
    }
    else if (ipstackType == kAlicloudIPv4only) {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] [IPv6-Test] detect IP stack type: IPv4-only");
    }
    else if (ipstackType == kAlicloudIPv6only) {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] [IPv6-Test] detect IP stack type: IPv6-only");
    }
    else {
        HttpdnsLogDebug("[AlicloudUtil-IPV6Help] [IPv6-Test] detect IP stack type: Unknown, set it as IPv4-only");
    }

    return ipstackType;

}

- (void)redetect {
    HttpdnsLogDebug("[AlicloudUtil-IPV6Help] redetect times = [ %ld ]", self.detectedTimes);

    __weak typeof(self) wself = self;

    dispatch_async(self.ipStackDetectingQueue, ^(){
        AlicloudIPStackType ipstackType = [wself detectIpStack];
        wself.detectedTimes++;

        // 终止重复探测条件
        if (ipstackType == kAlicloudIPdual || wself.detectedTimes >= ALICLOUD_UTILS_IPV6HELP_MAX_DETECT_TIMES) {
            wself.ipStackType = ipstackType;
            [wself timerinvalidate];

            HttpdnsLogDebug("[AlicloudUtil-IPV6Help] STOP redetect");
        }
    });
}

- (AlicloudIPStackType)currentDnsIPStackType {
    AlicloudIPStackType ipstackType = kAlicloudIPUnkown;

    res_state _res_state = malloc(sizeof(struct __res_state));
    if (0 == res_ninit(_res_state)) {
        union res_sockaddr_union *addr_union = malloc(_res_state->nscount * sizeof(union res_sockaddr_union));
        if ( !addr_union ) {
            res_nclose(_res_state);
            res_ndestroy(_res_state);
            free(_res_state);
            return ipstackType;
        }

        res_getservers(_res_state, addr_union, _res_state->nscount);

        char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];

        for (int i=0; i<_res_state->nscount; i++) {
            if (addr_union[i].sin6.sin6_family == AF_INET6) {
                if(inet_ntop(AF_INET6, &(addr_union[i].sin6.sin6_addr), addrBuf, INET6_ADDRSTRLEN)) {
                    HttpdnsLogDebug("[AlicloudUtil-IPV6Help] DNS[%d], IPv6: %@", i, [NSString stringWithUTF8String:addrBuf]);
                    ipstackType |= kAlicloudIPv6only;
                }

            }
            else if(addr_union[i].sin.sin_family == AF_INET) {
                if(inet_ntop(AF_INET, &(addr_union[i].sin.sin_addr), addrBuf, INET_ADDRSTRLEN)) {
                    HttpdnsLogDebug("[AlicloudUtil-IPV6Help] DNS[%d], IPv4: %@", i, [NSString stringWithUTF8String:addrBuf]);
                    ipstackType |= kAlicloudIPv4only;
                }
            }
        }

        free(addr_union);
    }

    res_nclose(_res_state);
    res_ndestroy(_res_state);
    free(_res_state);

    return ipstackType;
}

@end
