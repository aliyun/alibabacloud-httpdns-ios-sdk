/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#import "HttpdnsModel.h"
#import "HttpdnsConfig.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsIPRecord.h"


@implementation HttpdnsIpObject

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        self.ip = [aDecoder decodeObjectForKey:@"ip"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.ip forKey:@"ip"];
}

+ (NSArray<HttpdnsIpObject *> *)IPObjectsFromIPs:(NSArray<NSString *> *)IPs {
    NSMutableArray *IPObjects = [NSMutableArray arrayWithCapacity:IPs.count];
    for (NSString *IP in IPs) {
        HttpdnsIpObject *IPObject = [HttpdnsIpObject new];
        IPObject.ip = IP;
        [IPObjects addObject:IPObject];
    }
    return [IPObjects copy];
}

- (NSString *)description {
    return self.ip;
}

@end

@implementation HttpdnsHostObject
@synthesize ips = _ips;
@synthesize ip6s = _ip6s;

- (instancetype)init {
    _hostName = nil;
    _lastLookupTime = 0;
    _ttl = -1;
    _v4ttl = -1;
    _lastIPv4LookupTime = 0;
    _v6ttl = -1;
    _lastIPv6LookupTime = 0;
    _isLoadFromDB = NO;
    _ips = nil;
    _ip6s = nil;
    _queryingState = NO;
    _extra = nil;
    _ipRegion = @"";
    _ip6Region = @"";
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _hostName = [aDecoder decodeObjectForKey:@"hostName"];
        _lastLookupTime = [aDecoder decodeInt64ForKey:@"lastLookupTime"];
        _ttl = [aDecoder decodeInt64ForKey:@"ttl"];
        _v4ttl = [aDecoder decodeInt64ForKey:@"v4ttl"];
        _v6ttl = [aDecoder decodeInt64ForKey:@"v6ttl"];
        _ips = [aDecoder decodeObjectForKey:@"ips"];
        _ip6s = [aDecoder decodeObjectForKey:@"ip6s"];
        _queryingState = [aDecoder decodeBoolForKey:@"queryingState"];
        _extra = [aDecoder decodeObjectForKey:@"extra"];
        _ipRegion = [aDecoder decodeObjectForKey:@"ipRegion"];
        _ip6Region = [aDecoder decodeObjectForKey:@"ip6Region"];
        
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_hostName forKey:@"hostName"];
    [aCoder encodeInt64:_lastLookupTime forKey:@"lastLookupTime"];
    [aCoder encodeInt64:_ttl forKey:@"ttl"];
    [aCoder encodeInt64:_v4ttl forKey:@"v4ttl"];
    [aCoder encodeInt64:_lastIPv4LookupTime forKey:@"lastIPv4LookupTime"];
    [aCoder encodeInt64:_v6ttl forKey:@"v6ttl"];
    [aCoder encodeInt64:_lastIPv6LookupTime forKey:@"lastIPv6LookupTime"];
    [aCoder encodeObject:_ips forKey:@"ips"];
    [aCoder encodeObject:_ip6s forKey:@"ip6s"];
    [aCoder encodeBool:_queryingState forKey:@"queryingState"];
    [aCoder encodeObject:_hostName forKey:@"extra"];
    [aCoder encodeObject:_ipRegion forKey:@"ipRegion"];
    [aCoder encodeObject:_ip6Region forKey:@"ip6Region"];
    
}

- (BOOL)isExpiredWithQueryIPType:(HttpdnsQueryIPType)queryIPType {
    if (_ttl == -1) {
        HttpdnsLogDebug("This should never happen!!!");
        return NO;
    }
    if (_isLoadFromDB) {
        return YES;
    }
    
    int64_t currentEpoch = (int64_t)[[[NSDate alloc] init] timeIntervalSince1970];
    if (queryIPType & HttpdnsQueryIPTypeIpv4 && queryIPType & HttpdnsQueryIPTypeIpv6) {
        
        if (_lastIPv4LookupTime + _v4ttl <= currentEpoch) {
            return YES;
        }
        
        if (_lastIPv6LookupTime + _v6ttl <= currentEpoch) {
            return YES;
        }
        
    } else {
        if (queryIPType & HttpdnsQueryIPTypeIpv4) {
            return (_lastIPv4LookupTime + _v4ttl <= currentEpoch);
        }
        if (queryIPType & HttpdnsQueryIPTypeIpv6) {
            return (_lastIPv6LookupTime + _v6ttl <= currentEpoch);
        }
    }
    
    return NO;
}

+ (instancetype)hostObjectWithHostRecord:(HttpdnsHostRecord *)hostRecord {
    HttpdnsHostObject *hostObject = [HttpdnsHostObject new];
    [hostObject setHostName:hostRecord.host];
    [hostObject setLastLookupTime:[hostRecord.createAt timeIntervalSince1970]];
    [hostObject setTTL:hostRecord.TTL];
    [hostObject setExtra:hostRecord.extra];
    hostObject.ipRegion = hostRecord.ipRegion;
    hostObject.ip6Region = hostRecord.ip6Region;
    NSArray *ips = hostRecord.IPs;
    NSArray *ip6s = hostRecord.IP6s;
    if ([HttpdnsUtil isValidArray:ips]) {
        hostObject.ips = [HttpdnsIpObject IPObjectsFromIPs:ips];
        
        //设置ipv4 的ttl lookuptimer
        [hostObject setV4TTL:hostRecord.TTL];
        [hostObject setLastIPv4LookupTime:hostObject.getLastLookupTime];
        
    }
    if ([HttpdnsUtil isValidArray:ip6s]) {
        hostObject.ip6s = [HttpdnsIpObject IPObjectsFromIPs:ip6s];
        
        //设置ipv6 的ttl lookuptimer
        [hostObject setV6TTL:hostRecord.TTL];
        [hostObject setLastIPv6LookupTime:hostObject.getLastLookupTime];
        
    }
    [hostObject setIsLoadFromDB:YES];
    return hostObject;
}

- (NSArray<NSString *> *)getIPStrings {
    NSArray<HttpdnsIpObject *> *IPRecords = [self getIps];
    NSMutableArray<NSString *> *IPs = [NSMutableArray arrayWithCapacity:IPRecords.count];
    for (HttpdnsIpObject *IPObject in IPRecords) {
        [HttpdnsUtil safeAddObject:IPObject.ip toArray:IPs];
    }
    return [IPs copy];
}

- (NSArray *)getIps {
    id object_ = nil;
    @try {
        @synchronized (self) {
            object_ = _ips;
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), @"");
    }
    return object_;
}

- (void)setIps:(NSArray<HttpdnsIpObject *> *)ips {
    @synchronized (self) {
        _ips = ips;
    }
}


- (NSArray<HttpdnsIpObject *> *)getIp6s {
    id object_ = nil;
    @try {
        @synchronized (self) {
            object_ = _ip6s;
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), @"");
    }
    return object_;
}

- (void)setIp6s:(NSArray<HttpdnsIpObject *> *)ip6s {
    @synchronized (self) {
        _ip6s = ip6s;
    }
}



- (NSArray<NSString *> *)getIP6Strings {
    NSArray *getIP6Strings = nil;
    @try {
        @try {
            NSArray<HttpdnsIpObject *> *IP6Records = [self getIp6s];
            NSMutableArray<NSString *> *IPs = [NSMutableArray arrayWithCapacity:IP6Records.count];
            if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
                for (HttpdnsIpObject *IPObject in IP6Records) {
                    [HttpdnsUtil safeAddObject:IPObject.ip toArray:IPs];
                }
            }
            getIP6Strings = [IPs copy];
        } @catch (NSException *exception) {
            NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception.reason);
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception.reason);
    }
    return getIP6Strings;
}

- (NSString *)description {
    @try {
        if (![EMASTools isValidArray:_ip6s]) {
            return [NSString stringWithFormat:@"Host = %@ ips = %@ lastLookup = %lld ttl = %lld queryingState = %@ extra = %@ ipRegion = %@ ip6Region = %@",
                    _hostName, _ips, _lastLookupTime, _ttl, _queryingState ? @"YES" : @"NO", _extra, _ipRegion, _ip6Region];
        } else {
            return [NSString stringWithFormat:@"Host = %@ ips = %@ ip6s = %@ lastLookup = %lld ttl = %lld queryingState = %@ extra = %@ ipRegion = %@ ip6Region = %@",
                    _hostName, _ips, _ip6s, _lastLookupTime, _ttl, _queryingState ? @"YES" : @"NO", _extra, _ipRegion, _ip6Region];
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception.reason);
    }
    return [NSString stringWithFormat:@"Host = %@", _hostName];
}


@end
