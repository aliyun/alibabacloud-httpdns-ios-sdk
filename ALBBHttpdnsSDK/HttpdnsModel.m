//
//  HttpdnsModel.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsModel.h"
#import "HttpdnsConfig.h"

@implementation HttpdnsIpObject
@synthesize ip;

-(id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        ip = [aDecoder decodeObjectForKey:@"ip"];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:ip forKey:@"ip"];
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
        _lastLookupTime = [aDecoder decodeInt64ForKey:@"lastLookupTime"];
        _ttl = [aDecoder decodeInt64ForKey:@"ttl"];
        _ips = [aDecoder decodeObjectForKey:@"ips"];
        _currentState = [aDecoder decodeIntegerForKey:@"currentState"];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_hostName forKey:@"hostName"];
    [aCoder encodeInt64:_lastLookupTime forKey:@"lastLookupTime"];
    [aCoder encodeInt64:_ttl forKey:@"ttl"];
    [aCoder encodeObject:_ips forKey:@"ips"];
    [aCoder encodeInteger:_currentState forKey:@"currentState"];
}

-(BOOL)isExpired {
    long long currentEpoch = (long long)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl < currentEpoch) {
        _currentState = EXPIRED;
        return YES;
    }
    return NO;
}

-(BOOL)isInvalid {
    long long currentEpoch = (long long)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl + MAX_EXPIRED_ENDURE_TIME_IN_SEC < currentEpoch) {
        _currentState = INVALID;
        return YES;
    }
    return NO;
}
@end

@implementation HttpdnsToken : NSObject

-(NSString *)description {
    return [NSString stringWithFormat:@"Token: ak = %@ sk = %@ sToken = %@", _accessKeyId, _accessKeySecret, _securityToken];
}
@end