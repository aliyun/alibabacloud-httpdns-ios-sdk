//
//  HttpdnsModel.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsModel.h"

@implementation HttpdnsIpObject

-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _ip = [aDecoder decodeObjectForKey:@"ip"];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_ip forKey:@"ip"];
}

@end

@implementation HttpdnsHostObject

-(instancetype)init {
    _hostName = nil;
    _currentState = INITIALIZE;
    _lastLookupTime = 0;
    _ttl = -1;
    _ips = nil;
    return self;
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _hostName = [aDecoder decodeObjectForKey:@"hostName"];
        _currentState = [aDecoder decodeIntegerForKey:@"currentState"];
        _lastLookupTime = [aDecoder decodeInt64ForKey:@"lastLookupTime"];
        _ttl = [aDecoder decodeInt64ForKey:@"ttl"];
        _ips = [aDecoder decodeObjectForKey:@"ips"];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_hostName forKey:@"hostName"];
    [aCoder encodeInteger:_currentState forKey:@"currentState"];
    [aCoder encodeInt64:_lastLookupTime forKey:@"lastLookupTime"];
    [aCoder encodeInt64:_ttl forKey:@"ttl"];
    [aCoder encodeObject:_ips forKey:@"ips"];
}

-(BOOL)isExpired {
    long long currentEpoch = (long long)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl > currentEpoch) {
        return NO;
    }
    return YES;
}

@end

@implementation FederationToken


@end