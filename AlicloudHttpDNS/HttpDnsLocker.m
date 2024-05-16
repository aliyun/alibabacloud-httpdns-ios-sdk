//
//  HttpDnsLocker.m
//  AlicloudHttpDNS
//
//  Created by 王贇 on 2023/8/16.
//  Copyright © 2023 alibaba-inc.com. All rights reserved.
//

#import "HttpDnsLocker.h"
#import "HttpdnsService.h"

@implementation HttpDnsLocker {
    NSMutableDictionary<NSString*, NSLock*> *_v4LockMap;
    NSMutableDictionary<NSString*, NSLock*> *_v6LockMap;
    NSMutableDictionary<NSString*, NSLock*> *_v4v6LockMap;
}

+ (instancetype)sharedInstance {
    static HttpDnsLocker *locker = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        locker = [[HttpDnsLocker alloc] init];
    });
    return locker;
}

- (instancetype)init {
    if (self = [super init]) {
        _v4LockMap = [NSMutableDictionary dictionary];
        _v6LockMap = [NSMutableDictionary dictionary];
        _v4v6LockMap = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)lock:(NSString *)host queryType:(HttpdnsQueryIPType)queryIpType {
    NSLock *condition = [self getLock:host queryType:queryIpType];

    if (condition) {
        [condition lock];
    }
}

- (void)unlock:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
    NSLock *condition = [self getLock:host queryType:queryType];
    if (condition) {
        [condition unlock];
    }
}

- (NSLock *)getLock:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
    if (queryType == HttpdnsQueryIPTypeIpv4) {
        NSLock *condition = [_v4LockMap objectForKey:host];
        if (!condition) {
            condition = [[NSLock alloc] init];
            [_v4LockMap setObject:condition forKey:host];
        }
        return condition;
    } else if (queryType == HttpdnsQueryIPTypeIpv6) {
        NSLock *condition = [_v6LockMap objectForKey:host];
        if (!condition) {
            condition = [[NSLock alloc] init];
            [_v6LockMap setObject:condition forKey:host];
        }
        return condition;
    } else {
        NSLock *condition = [_v4v6LockMap objectForKey:host];
        if (!condition) {
            condition = [[NSLock alloc] init];
            [_v4v6LockMap setObject:condition forKey:host];
        }
        return condition;
    }
}

@end
