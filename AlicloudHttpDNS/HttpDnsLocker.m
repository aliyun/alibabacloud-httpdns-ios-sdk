//
//  HttpDnsLocker.m
//  AlicloudHttpDNS
//
//  Created by 王贇 on 2023/8/16.
//  Copyright © 2023 alibaba-inc.com. All rights reserved.
//

#import "HttpDnsLocker.h"
#import "HttpdnsServiceProvider.h"

@implementation HttpDnsLocker {
    NSMutableDictionary<NSString*, NSCondition*> *_v4LockMap;
    NSMutableDictionary<NSString*, NSCondition*> *_v6LockMap;
    NSMutableDictionary<NSString*, NSCondition*> *_v4v6LockMap;
}

- (instancetype)init {
    if (self = [super init]) {
        _v4LockMap = [NSMutableDictionary dictionary];
        _v6LockMap = [NSMutableDictionary dictionary];
        _v4v6LockMap = [NSMutableDictionary dictionary];
    }
    return self;
}

-(void)lock:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
    NSCondition *condition = [[NSCondition alloc] init];
    if (queryType == HttpdnsQueryIPTypeIpv4) {
        [_v4LockMap setObject:condition forKey:host];
    } else if (queryType == HttpdnsQueryIPTypeIpv6) {
        [_v6LockMap setObject:condition forKey:host];
    } else {
        [_v4v6LockMap setObject:condition forKey:host];
    }
}

-(void)wait:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
    NSCondition *condition;
    if (queryType == HttpdnsQueryIPTypeIpv4) {
        condition = [_v4LockMap objectForKey:host];
    } else if (queryType == HttpdnsQueryIPTypeIpv6) {
        condition = [_v6LockMap objectForKey:host];
    } else {
        condition = [_v4v6LockMap objectForKey:host];
    }
    if (condition) {
        NSTimeInterval serviceTimeout = [HttpDnsService sharedInstance].timeoutInterval;
        NSTimeInterval lockTimeout;
        //锁的超时时间最大为5s
        if (serviceTimeout > 5) {
            lockTimeout = 5;
        } else {
            lockTimeout = serviceTimeout;
        }
        
        [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:lockTimeout]];
    }
}

-(void)unlock:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
    NSCondition *condition;
    if (queryType == HttpdnsQueryIPTypeIpv4) {
        condition = [_v4LockMap objectForKey:host];
    } else if (queryType == HttpdnsQueryIPTypeIpv6) {
        condition = [_v6LockMap objectForKey:host];
    } else {
        condition = [_v4v6LockMap objectForKey:host];
    }
    if (condition) {
        [condition unlock];
    }
}

-(void)signal:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
    NSCondition *condition;
    if (queryType == HttpdnsQueryIPTypeIpv4) {
        condition = [_v4LockMap objectForKey:host];
    } else if (queryType == HttpdnsQueryIPTypeIpv6) {
        condition = [_v6LockMap objectForKey:host];
    } else {
        condition = [_v4v6LockMap objectForKey:host];
    }
    if (condition) {
        [condition signal];
    }
}

@end
