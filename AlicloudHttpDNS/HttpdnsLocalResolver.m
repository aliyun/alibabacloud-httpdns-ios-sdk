//
//  HttpdnsLocalResolver.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/16.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsLocalResolver.h"
#import <netdb.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <sys/socket.h>

#import "HttpdnsService.h"
#import "HttpdnsUtil.h"
#import "HttpdnsHostObject.h"

@implementation HttpdnsLocalResolver

+ (instancetype)sharedInstance {
    static HttpdnsLocalResolver *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HttpdnsLocalResolver alloc] init];
    });
    return instance;
}

- (HttpdnsHostObject *)resolve:(HttpdnsRequest *)request {
    // 1. 验证输入参数
    NSString *host = request.host;
    if (host.length == 0) {
        return nil; // 没有主机名可解析
    }

    // 2. 准备DNS解析配置
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;     // 同时支持IPv4和IPv6
    hints.ai_socktype = SOCK_STREAM;   // TCP (对DNS解析来说通常不重要)

    // 3. 执行getaddrinfo解析
    struct addrinfo *res = NULL;
    int ret = getaddrinfo([host UTF8String], NULL, &hints, &res);
    if (ret != 0 || res == NULL) {
        // DNS解析失败
        if (res) {
            freeaddrinfo(res);
        }
        return nil;
    }

    // 4. 收集所有IPv4和IPv6地址
    NSMutableArray<NSString *> *ipv4Array = [NSMutableArray array];
    NSMutableArray<NSString *> *ipv6Array = [NSMutableArray array];

    for (struct addrinfo *p = res; p != NULL; p = p->ai_next) {
        if (p->ai_family == AF_INET || p->ai_family == AF_INET6) {
            char hostBuffer[NI_MAXHOST];
            memset(hostBuffer, 0, sizeof(hostBuffer));

            if (getnameinfo(p->ai_addr, (socklen_t)p->ai_addrlen,
                            hostBuffer, sizeof(hostBuffer),
                            NULL, 0, NI_NUMERICHOST) == 0) {
                NSString *ipString = [NSString stringWithUTF8String:hostBuffer];
                if (p->ai_family == AF_INET) {
                    [ipv4Array addObject:ipString];
                } else {
                    [ipv6Array addObject:ipString];
                }
            }
        }
    }
    freeaddrinfo(res);

    // 5. 根据queryIpType确定保留哪些IP类型
    BOOL wantIPv4 = NO;
    BOOL wantIPv6 = NO;

    switch (request.queryIpType) {
        case HttpdnsQueryIPTypeAuto:
            // Auto模式：如果有IPv4则始终返回，如果有IPv6则也包含
            // 无条件设置wantIPv4为YES
            wantIPv4 = YES;
            // 如果DNS返回了IPv6地址，则也包含IPv6
            wantIPv6 = (ipv6Array.count > 0);
            break;

        case HttpdnsQueryIPTypeIpv4:
            wantIPv4 = YES;
            break;

        case HttpdnsQueryIPTypeIpv6:
            wantIPv6 = YES;
            break;

        case HttpdnsQueryIPTypeBoth:
            wantIPv4 = YES;
            wantIPv6 = YES;
            break;
    }

    // 6. 构建最终的HttpdnsIpObject数组
    NSMutableArray<HttpdnsIpObject *> *v4IpObjects = [NSMutableArray array];
    NSMutableArray<HttpdnsIpObject *> *v6IpObjects = [NSMutableArray array];

    if (wantIPv4) {
        for (NSString *ipStr in ipv4Array) {
            HttpdnsIpObject *ipObj = [[HttpdnsIpObject alloc] init];
            [ipObj setIp:ipStr];  // ipObj.ip = ipStr
            // connectedRT默认为0
            [v4IpObjects addObject:ipObj];
        }
    }
    if (wantIPv6) {
        for (NSString *ipStr in ipv6Array) {
            HttpdnsIpObject *ipObj = [[HttpdnsIpObject alloc] init];
            [ipObj setIp:ipStr];
            [v6IpObjects addObject:ipObj];
        }
    }

    // 7. 创建并填充HttpdnsHostObject
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    [hostObject setHostName:host];              // hostName = request.host
    [hostObject setV4Ips:v4IpObjects];
    [hostObject setV6Ips:v6IpObjects];

    // IPv4和IPv6的默认TTL为60秒
    [hostObject setV4TTL:60];
    [hostObject setV6TTL:60];

    // 自定义ttl
    [HttpdnsUtil processCustomTTL:hostObject forHost:host];

    // 当前时间(自1970年以来的秒数)
    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];

    // 更新最后查询时间
    [hostObject setLastIPv4LookupTime:now];
    [hostObject setLastIPv6LookupTime:now];

    // 标记是否没有IPv4或IPv6记录
    [hostObject setHasNoIpv4Record:(v4IpObjects.count == 0)];
    [hostObject setHasNoIpv6Record:(v6IpObjects.count == 0)];

    // 如果需要，可以在这里设置clientIp或额外字段
    // 现在保留为默认值/空

    return hostObject;
}

@end
