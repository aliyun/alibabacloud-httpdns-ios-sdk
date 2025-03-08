//
//  AlicloudIPv6PrefixResolver.m
//  AlicloudUtils
//
//  Created by lingkun on 16/5/16.
//  Edited by lingkun on 17/7/26.
//  Copyright © 2016年 Ali. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIDevice.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>

#import "HttpdnsLog_Internal.h"
#import "AlicloudIPv6PrefixResolver.h"

#define IPV6_PREFIX_32       32
#define IPV6_PREFIX_40       40
#define IPV6_PREFIX_48       48
#define IPV6_PREFIX_56       56
#define IPV6_PREFIX_64       64
#define IPV6_PREFIX_96       96

#define IPV6_PREFIX_LENGTH_COUNT 7

static NSString *const TAG = @"AlicloudIPv6PrefixResolver";

static const __uint8_t IPV6_PREFIX_LENGTHS[IPV6_PREFIX_LENGTH_COUNT] = {
    IPV6_PREFIX_32,
    IPV6_PREFIX_40,
    IPV6_PREFIX_48,
    IPV6_PREFIX_56,
    IPV6_PREFIX_64,
    IPV6_PREFIX_96
};

static const __uint8_t WELL_KNOWN_V6_PREFIX[16] =
{0x00, 0x64, 0xff, 0x9b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

/**
 *  192.0.0.170 | 192.0.0.171
 *  参考：https://tools.ietf.org/rfc/rfc7050.txt
 */
static const __uint8_t IPV4_ONLY_ARPA_0[4] = {0xc0, 0x00, 0x00, 0xaa};
static const __uint8_t IPV4_ONLY_ARPA_1[4] = {0xc0, 0x00, 0x00, 0xab};

typedef enum {
    IPv6PrefixUnResolved = 0,
    IPv6PrefixResolving,
    IPv6PrefixResolved
} IPv6PrefixResolveStatus;

@implementation AlicloudIPv6PrefixResolver
{
    IPv6PrefixResolveStatus ipv6PrefixResolveStatus;
    __uint8_t ipv6Prefix[16];
    int prefixLen;
    int forcedType;
}

- (instancetype)init {
    if (self = [super init]) {
        ipv6PrefixResolveStatus = IPv6PrefixUnResolved;
        memcpy(ipv6Prefix, WELL_KNOWN_V6_PREFIX, sizeof(WELL_KNOWN_V6_PREFIX));
        prefixLen = IPV6_PREFIX_96;
        forcedType = 0;
    }
    return self;
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

/**
 *  更新IPv6 Prefix
 */
- (void)updateIPv6Prefix {
    @synchronized(self) {
        ipv6PrefixResolveStatus = IPv6PrefixUnResolved;
        [self resolveIPv6Prefix:ipv6Prefix];
    }
}

/**
 *  >= iOS 9.2, 基于getaddrinfo()完成v4 > v6的地址转换 【模拟器测试时getaddrinfo()接口报错，真机测试正常】
 *  参考苹果官方文档：
 *  https://developer.apple.com/library/content/documentation/NetworkingInternetWeb/Conceptual/NetworkingOverview/UnderstandingandPreparingfortheIPv6Transition/UnderstandingandPreparingfortheIPv6Transition.html#//apple_ref/doc/uid/TP40010220-CH213-DontLinkElementID_4
 */
- (NSString *)convertBySystem:(NSString *)ipv4Addr {
    HttpdnsLogDebug("Convert address by system.");
    NSString *ipv6Addr;
    struct addrinfo hints, *addr = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = PF_INET6;
    int res = getaddrinfo([ipv4Addr UTF8String], NULL, &hints, &addr);
    if (res != 0) {
        return ipv4Addr;
    }

    while (addr && (addr->ai_addr->sa_family == AF_INET6)) {
        struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)(addr->ai_addr);
        if (!addr6) {
            addr = addr->ai_next;
            continue;
        }
        /* convert format */
        char addrBuf[MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN)];
        if (inet_ntop(AF_INET6, &(addr6->sin6_addr), addrBuf, INET6_ADDRSTRLEN)) {
            ipv6Addr = [NSString stringWithUTF8String:addrBuf];
            break;
        }
        addr = addr->ai_next;
    }
    return ipv6Addr;
}

- (NSString *)convertByPrefix:(NSString *)ipv4Addr {
    HttpdnsLogDebug("Convert address by prefix.");
    __uint8_t ipv6[16] = {0x00};
    __uint8_t length = [self resolveIPv6Prefix:ipv6];

    if (length <= 0) {
        return ipv4Addr;
    }

    in_addr_t addr_v4 = inet_addr([ipv4Addr UTF8String]);

    // get the prefix end index
    __uint8_t idx = length >> 3;

    if (length == IPV6_PREFIX_32 || length == IPV6_PREFIX_96) { //32 bits or 96 bits
        ipv6[idx+0] |= (__uint8_t)(addr_v4>>0 & 0xff);
        ipv6[idx+1] |= (__uint8_t)(addr_v4>>8 & 0xff);
        ipv6[idx+2] |= (__uint8_t)(addr_v4>>16 & 0xff);
        ipv6[idx+3] |= (__uint8_t)(addr_v4>>24 & 0xff);
    } else if (length == IPV6_PREFIX_40) { //40 bits  :a.b.c.0.d
        ipv6[idx+0] |= (__uint8_t)(addr_v4>>0 & 0xff);
        ipv6[idx+1] |= (__uint8_t)(addr_v4>>8 & 0xff);
        ipv6[idx+2] |= (__uint8_t)(addr_v4>>16 & 0xff);
        ipv6[idx+4] |= (__uint8_t)(addr_v4>>24 & 0xff);
    } else if (length == IPV6_PREFIX_48) { //48 bits   :a.b.0.c.d
        ipv6[idx+0] |= (__uint8_t)(addr_v4>>0 & 0xff);
        ipv6[idx+1] |= (__uint8_t)(addr_v4>>8 & 0xff);
        ipv6[idx+3] |= (__uint8_t)(addr_v4>>16 & 0xff);
        ipv6[idx+4] |= (__uint8_t)(addr_v4>>24 & 0xff);
    } else if (length == IPV6_PREFIX_56) { //56 bits   :a.0.b.c.d
        ipv6[idx+0] |= (__uint8_t)(addr_v4>>0 & 0xff);
        ipv6[idx+2] |= (__uint8_t)(addr_v4>>8 & 0xff);
        ipv6[idx+3] |= (__uint8_t)(addr_v4>>16 & 0xff);
        ipv6[idx+4] |= (__uint8_t)(addr_v4>>24 & 0xff);
    } else if (length == IPV6_PREFIX_64) { //64 bits   :0.a.b.c.d
        ipv6[idx+1] |= (__uint8_t)(addr_v4>>0 & 0xff);
        ipv6[idx+2] |= (__uint8_t)(addr_v4>>8 & 0xff);
        ipv6[idx+3] |= (__uint8_t)(addr_v4>>16 & 0xff);
        ipv6[idx+4] |= (__uint8_t)(addr_v4>>24 & 0xff);
    }

    // 构造IPv6的结构
    char addr_text[MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN)];
    if(inet_ntop(AF_INET6, ipv6, addr_text, INET6_ADDRSTRLEN)) {
        NSString *ret = [NSString stringWithUTF8String:addr_text];
        return ret;
    }
    return ipv4Addr;
}

- (__uint8_t)resolveIPv6Prefix:(__uint8_t *)prefix {

    if (!prefix) {
        return 0;
    }
    __uint8_t len = prefixLen;
    memcpy(prefix, ipv6Prefix, sizeof(ipv6Prefix));
    @synchronized(self) {
        if (ipv6PrefixResolveStatus == IPv6PrefixUnResolved ) {
            ipv6PrefixResolveStatus = IPv6PrefixResolving;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                struct addrinfo hints, *addr = NULL;
                memset(&hints, 0, sizeof(hints));
                hints.ai_family = PF_INET6;
                hints.ai_socktype = SOCK_STREAM;
                hints.ai_flags = AI_ADDRCONFIG|AI_V4MAPPED;

                if (0 != getaddrinfo("ipv4only.arpa", NULL, &hints, &addr)) {
                    ipv6PrefixResolveStatus = IPv6PrefixUnResolved;
                    return;
                }

                if (addr && AF_INET6 == addr->ai_addr->sa_family) {
                    struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)(addr->ai_addr);
                    if ( !addr6 ) {
                        ipv6PrefixResolveStatus = IPv6PrefixUnResolved;
                        return;
                    }
                    __uint8_t* u8 = addr6->sin6_addr.__u6_addr.__u6_addr8;

                    __uint8_t len = 0;
                    for (int index = 0; index < IPV6_PREFIX_LENGTH_COUNT; index++) {
                        if ([self ipv4OnlyIP:u8 matchPrefixBitsCount:IPV6_PREFIX_LENGTHS[index]]) {
                            len = IPV6_PREFIX_LENGTHS[index];
                        }
                    }
                    if (len > 0) {
                        memcpy(ipv6Prefix, u8, len >> 3);
                        prefixLen = len;
                        ipv6PrefixResolveStatus = IPv6PrefixResolved;
                    } else {
                        ipv6PrefixResolveStatus = IPv6PrefixUnResolved;
                    }
                }
                freeaddrinfo(addr);
            });
        }
    }
    return len;
}

- (NSString *)convertIPv4toIPv6:(NSString *)ipv4 {
    if (!ipv4) {
        return ipv4;
    }

    // for test
    if (forcedType == 1) {
        return [self convertBySystem:ipv4];
    } else if (forcedType == 2) {
        return [self convertByPrefix:ipv4];
    }   // for test

#if TARGET_OS_SIMULATOR
    return [self convertByPrefix:ipv4];
#else
    if ([self isSystemVersionBiggerThanIOS9]) {
        return [self convertBySystem:ipv4];
    } else {
        return [self convertByPrefix:ipv4];
    }
#endif
}

/*
 
 IPv4-Eembedded IPv6 Address Format:
 
 +--+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 |PL| 0-------------32--40--48--56--64--72--80--88--96--104---------|
 +--+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 |32|     prefix    |v4(32)         | u | suffix                    |
 +--+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 |40|     prefix        |v4(24)     | u |(8)| suffix                |
 +--+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 |48|     prefix            |v4(16) | u | (16)  | suffix            |
 +--+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 |56|     prefix                |(8)| u |  v4(24)   | suffix        |
 +--+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 |64|     prefix                    | u |   v4(32)      | suffix    |
 +--+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 |96|     prefix                                    |    v4(32)     |
 +--+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 
 */
- (BOOL)ipv4OnlyIP:(const __uint8_t *)ip matchPrefixBitsCount:(__uint8_t)count {
    int idx = count >> 3;
    NSLog(@"count: %d, idx: %d", count, idx);
    if (count == IPV6_PREFIX_32 || count == IPV6_PREFIX_96) {
        if (ip[idx+0] == IPV4_ONLY_ARPA_0[0] &&
            ip[idx+1] == IPV4_ONLY_ARPA_0[1] &&
            ip[idx+2] == IPV4_ONLY_ARPA_0[2] &&
            (ip[idx+3] == IPV4_ONLY_ARPA_0[3] || ip[idx+3] == IPV4_ONLY_ARPA_1[3]) ) {
            return YES;
        }
    } else if (count == IPV6_PREFIX_40) {
        if (ip[idx+0] == IPV4_ONLY_ARPA_0[0] &&
            ip[idx+1] == IPV4_ONLY_ARPA_0[1] &&
            ip[idx+2] == IPV4_ONLY_ARPA_0[2] &&
            (ip[idx+4] == IPV4_ONLY_ARPA_0[3] || ip[idx+4] == IPV4_ONLY_ARPA_1[3]) ) {
            return YES;
        }
    } else if (count == IPV6_PREFIX_48) {
        if (ip[idx+0] == IPV4_ONLY_ARPA_0[0] &&
            ip[idx+1] == IPV4_ONLY_ARPA_0[1] &&
            ip[idx+3] == IPV4_ONLY_ARPA_0[2] &&
            (ip[idx+4] == IPV4_ONLY_ARPA_0[3] || ip[idx+4] == IPV4_ONLY_ARPA_1[3]) ) {
            return YES;
        }
    } else if (count == IPV6_PREFIX_56) {
        if (ip[idx+0] == IPV4_ONLY_ARPA_0[0] &&
            ip[idx+2] == IPV4_ONLY_ARPA_0[1] &&
            ip[idx+3] == IPV4_ONLY_ARPA_0[2] &&
            (ip[idx+4] == IPV4_ONLY_ARPA_0[3] || ip[idx+4] == IPV4_ONLY_ARPA_1[3]) ) {
            return YES;
        }
    } else if (count == IPV6_PREFIX_64) {
        if (ip[idx+1] == IPV4_ONLY_ARPA_0[0] &&
            ip[idx+2] == IPV4_ONLY_ARPA_0[1] &&
            ip[idx+3] == IPV4_ONLY_ARPA_0[2] &&
            (ip[idx+4] == IPV4_ONLY_ARPA_0[3] || ip[idx+4] == IPV4_ONLY_ARPA_1[3]) ) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isSystemVersionBiggerThanIOS9 {
    static BOOL res = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        res = ([[[UIDevice currentDevice] systemVersion] compare:@"9.2" options:NSNumericSearch] != NSOrderedAscending);
    });
    return res;
}

/*******************************************************/
/*             For Test                                */
/*******************************************************/

/**
 强制设定v4 > v6转换类型
 
 @param type 1: 强制基于系统转换； 2: 强制基于前缀转换；other: 非强制
 */
- (void)forceConvertByType:(int)type {
    forcedType = type;
}

@end
