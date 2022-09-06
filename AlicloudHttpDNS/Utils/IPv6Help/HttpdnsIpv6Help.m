//
//  HttpdnsIpv6Help.m
//  AlicloudHttpDNS
//
//  Created by yannan on 2022/9/6.
//  Copyright © 2022 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsIpv6Help.h"

#import <arpa/inet.h>
#import <net/if.h>
#import <netdb.h>
#import <resolv.h>
#import <dns.h>
#import "getgateway.h"
#import "socket_udp.h"
#import "HttpdnsLog_Internal.h"
#import "AlicloudUtils/AlicloudUtils.h"

#import <UIKit/UIDevice.h>

#define HTTPDNS_IPV6HELP_MAX_DETECT_TIMES     20
#define HTTPDNS_IPV6HELP_DETECT_INTERVAL      5



@interface HttpdnsIpv6Help ()

@property (nonatomic, strong)   dispatch_queue_t    ipStackDetectingQueue;   // 同步，防止多线程同时触发
//@property (nonatomic, strong)   dispatch_queue_t    wifiIPv6DetectionQueue;  // 同步，防止多线程同时触发
@property (nonatomic, assign)   HttpdnsIPStackType       ipStackType;
@property (nonatomic, strong)   NSTimer             *timer;
@property (atomic, assign)      NSUInteger          detectedTimes;


@end

@implementation HttpdnsIpv6Help

+ (instancetype)sharedInstance {
    static HttpdnsIpv6Help *instance;
    static dispatch_once_t pred = 0;
    dispatch_once(&pred, ^{
        instance = [[HttpdnsIpv6Help alloc] init];
    });

    return instance;
}

+ (BOOL)deviceSystemIsLargeIOS9 {
    static BOOL __ios9__ = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __ios9__ = [[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0;
    });

    return __ios9__;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ipStackDetectingQueue  = dispatch_queue_create("httpdns.ipstackdetecting.queue", DISPATCH_QUEUE_SERIAL);
        _ipStackType            = kHttpdnsIPUnkown;
        _detectedTimes          = 0;
        
        
        //注册网络切换通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(networkChanged:)
                                                     name:ALICLOUD_NETWOEK_STATUS_NOTIFY
                                                   object:nil];
        
        
    }

    return self;
}




- (BOOL)isIPv6only {
    if (self.ipStackType != kHttpdnsIPUnkown) {
        return (self.ipStackType == kHttpdnsIPv6only);
    }

    self.ipStackType = [self currentIpStackType];
    return (self.ipStackType == kHttpdnsIPv6only);
}

- (HttpdnsIPStackType)currentIpStackType {
    HttpdnsIPStackType type = self.ipStackType;
    if (type != kHttpdnsIPUnkown) {
        return type;
    }

    // 同步探测，但是放在同一个同步队列里
    dispatch_sync(self.ipStackDetectingQueue, ^(){
        // 双重判断，避免重复探测
        if (self.ipStackType == kHttpdnsIPUnkown) {
            self.ipStackType = [self detectIpStack];

            // 注意：因为双栈情况下v4 ip 与 v6 ip 分配有先后，且时间不定，所以需要间隔一段时间后再查询一遍
            // 最大重复次数：20次
            if (self.ipStackType != kHttpdnsIPdual && self.detectedTimes == 0) {
                [self timerinvalidate];
                self.timer = [NSTimer scheduledTimerWithTimeInterval:HTTPDNS_IPV6HELP_DETECT_INTERVAL target:self selector:@selector(redetect) userInfo:nil repeats:YES];
            }
        }
    });

    return self.ipStackType;
}

- (void)reset {
    HttpdnsLogDebug("[HTTPDNS-IPV6Help] reset...");

    dispatch_sync(self.ipStackDetectingQueue, ^(){
        [self timerinvalidate];
        self.detectedTimes = 0;

        self.ipStackType = kHttpdnsIPUnkown;
    });

}


- (HttpdnsIPStackType)detectIpStack {
    
    char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];
    
    // S0: 先获取IPv6 gateway: 没有IPv6网关，认为是IPv4-only网络
    struct in6_addr addr6;
    if (-1 == getdefaultgateway6(&addr6)) {
        return kHttpdnsIPv4only;
    }
    if (inet_ntop(AF_INET6, &addr6, addrBuf, INET6_ADDRSTRLEN)) {
        HttpdnsLogDebug("[HTTPDNS-IPV6Help] IPv6 gateway: %@", [NSString stringWithUTF8String:addrBuf]);
    }
    
    // S1: 获取IPv4 gateway: 没有IPv4网关，认为是IPv6-only网络
    struct in_addr addr4;
    if (-1 == getdefaultgateway(&addr4)) {
        return kHttpdnsIPv6only;
    }
    if (inet_ntop(AF_INET, &addr4, addrBuf, INET_ADDRSTRLEN)) {
        HttpdnsLogDebug("[HTTPDNS-IPV6Help] IPv4 gateway: %@", [NSString stringWithUTF8String:addrBuf]);
    }
    
    // S2: UDP 探测
    HttpdnsIPStackType ipstackType = kHttpdnsIPUnkown;
    if ( test_udp_connect_ipv4() ) {
        ipstackType |= kHttpdnsIPv4only;
        HttpdnsLogDebug("[HTTPDNS-IPV6Help] IPv4 UDP connect success");
    }
    if ( test_udp_connect_ipv6() ) {
        HttpdnsLogDebug("[HTTPDNS-IPV6Help] IPv6 UDP connect success");
        ipstackType |= kHttpdnsIPv6only;
    }
    
    // S3: 在 iOS 版本<9.0 的情况下，如果是双栈，需要进一步通过 DNS 判断
    if (ipstackType==kHttpdnsIPdual && ![HttpdnsIpv6Help deviceSystemIsLargeIOS9] ) {
        ipstackType = [self currentDnsIPStackType];
    }
    
    
    if (ipstackType == kHttpdnsIPdual) {
        HttpdnsLogDebug("[HTTPDNS-IPV6Help] [IPv6-Test] detect IP stack type: Dual-Stack");
    }
    else if (ipstackType == kHttpdnsIPv4only) {
        HttpdnsLogDebug("[HTTPDNS-IPV6Help] [IPv6-Test] detect IP stack type: IPv4-only");
    }
    else if (ipstackType == kHttpdnsIPv6only) {
        HttpdnsLogDebug("[HTTPDNS-IPV6Help] [IPv6-Test] detect IP stack type: IPv6-only");
    }
    else {
        HttpdnsLogDebug("[HTTPDNS-IPV6Help] [IPv6-Test] detect IP stack type: Unknown, set it as IPv4-only");
    }
    
    return ipstackType;
    
}





- (void)redetect {
    HttpdnsLogDebug("[HTTPDNS-IPV6Help] redetect times = [ %ld ]", self.detectedTimes);

    __weak typeof(self) wself = self;

    dispatch_async(self.ipStackDetectingQueue, ^(){
        HttpdnsIPStackType ipstackType = [wself detectIpStack];
        wself.detectedTimes++;

        // 终止重复探测条件
        if (ipstackType == kHttpdnsIPdual || wself.detectedTimes >= HTTPDNS_IPV6HELP_MAX_DETECT_TIMES) {
            wself.ipStackType = ipstackType;
            [wself timerinvalidate];

            HttpdnsLogDebug("[HTTPDNS-IPV6Help] STOP redetect");
        }
    });
}


- (HttpdnsIPStackType)currentDnsIPStackType {
    HttpdnsIPStackType ipstackType = kHttpdnsIPUnkown;

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
                    HttpdnsLogDebug("[HTTPDNS-IPV6Help] DNS[%d], IPv6: %@", i, [NSString stringWithUTF8String:addrBuf]);
                    ipstackType |= kHttpdnsIPv6only;
                }

            }
            else if(addr_union[i].sin.sin_family == AF_INET) {
                if(inet_ntop(AF_INET, &(addr_union[i].sin.sin_addr), addrBuf, INET_ADDRSTRLEN)) {
                    HttpdnsLogDebug("[HTTPDNS-IPV6Help] DNS[%d], IPv4: %@", i, [NSString stringWithUTF8String:addrBuf]);
                    ipstackType |= kHttpdnsIPv4only;
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


- (void)timerinvalidate {
    if (_timer) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)networkChanged:(NSNotification *)notifi {
    [self reset];
    [self isIPv6only];
}




@end
