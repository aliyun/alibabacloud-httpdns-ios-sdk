//
//  HttpdnsModel.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsModel.h"


@implementation HttpdnsHostObject

-(instancetype)init {
    _hostName = nil;
    _currentState = INITIALIZE;
    _lastLookupTime = 0;
    _ttl = -1;
    _ips = nil;
    return self;
}

-(BOOL)isExpired {
    long long currentEpoch = (long long)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl > currentEpoch) {
        return NO;
    }
    return YES;
}
@end