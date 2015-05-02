//
//  HttpdnsModel.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsModel.h"


@implementation HttpdnsHostObject

-(instancetype)initWithHostName:(NSString *)hostName inState:(HostState) state {
    _hostName = hostName;
    _currentState = state;
    return self;
}

-(BOOL)isExspired {
    long long currentEpoch = (long long)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl > currentEpoch) {
        return YES;
    }
    return NO;
}
@end