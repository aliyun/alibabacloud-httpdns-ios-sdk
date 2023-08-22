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

-(NSCondition *)lock:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
    NSCondition *condition;
    if (queryType == HttpdnsQueryIPTypeIpv4) {
        condition = [_v4LockMap objectForKey:host];
        if (condition == nil) {
            condition = [[NSCondition alloc] init];
            [_v4LockMap setObject:condition forKey:host];
        }
    } else if (queryType == HttpdnsQueryIPTypeIpv6) {
        condition = [_v6LockMap objectForKey:host];
        if (condition == nil) {
            condition = [[NSCondition alloc] init];
            [_v6LockMap setObject:condition forKey:host];
        }
    } else {
        condition = [_v4v6LockMap objectForKey:host];
        if (condition == nil) {
            condition = [[NSCondition alloc] init];
            [_v4v6LockMap setObject:condition forKey:host];
        }
    }
    
    if (condition) {
        [condition lock];
    }
    
    return condition;
}

-(BOOL)wait:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
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
        NSLog(@"###### httpDnsService timeout is %f", serviceTimeout);
        NSTimeInterval lockTimeout;
        //锁的超时时间最大为5s
        if (serviceTimeout > 5) {
            lockTimeout = 5;
        } else {
            lockTimeout = serviceTimeout;
        }
        
        NSLog(@"###### final lockTimeout is: %f", lockTimeout);
        
        return [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:lockTimeout]];
    }
    return NO;
}

-(void)unlock:(NSString *)host queryType:(HttpdnsQueryIPType)queryType {
    NSCondition *condition;
    if (queryType == HttpdnsQueryIPTypeIpv4) {
        condition = [_v4LockMap objectForKey:host];
        [_v4LockMap removeObjectForKey: host];
    } else if (queryType == HttpdnsQueryIPTypeIpv6) {
        condition = [_v6LockMap objectForKey:host];
        [_v6LockMap removeObjectForKey:host];
    } else {
        condition = [_v4v6LockMap objectForKey:host];
        [_v4v6LockMap removeObjectForKey:host];
    }
    if (condition) {
        [condition unlock];
    }
}


@end
