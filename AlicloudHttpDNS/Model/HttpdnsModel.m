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
#import "HttpdnsIPv6Manager.h"

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

- (instancetype)init {
    _hostName = nil;
    _lastLookupTime = 0;
    _ttl = -1;
    _isLoadFromDB = NO;
    _ips = nil;
    _ip6s = nil;
    _queryingState = NO;
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _hostName = [aDecoder decodeObjectForKey:@"hostName"];
        _lastLookupTime = [aDecoder decodeInt64ForKey:@"lastLookupTime"];
        _ttl = [aDecoder decodeInt64ForKey:@"ttl"];
        _ips = [aDecoder decodeObjectForKey:@"ips"];
        _ip6s = [aDecoder decodeObjectForKey:@"ip6s"];
        _queryingState = [aDecoder decodeBoolForKey:@"queryingState"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_hostName forKey:@"hostName"];
    [aCoder encodeInt64:_lastLookupTime forKey:@"lastLookupTime"];
    [aCoder encodeInt64:_ttl forKey:@"ttl"];
    [aCoder encodeObject:_ips forKey:@"ips"];
    [aCoder encodeObject:_ip6s forKey:@"ip6s"];
    [aCoder encodeBool:_queryingState forKey:@"queryingState"];
}

- (BOOL)isExpired {
    if (_ttl == -1) {
        HttpdnsLogDebug("This should never happen!!!");
        return NO;
    }
    if (_isLoadFromDB) {
        return YES;
    }
    int64_t currentEpoch = (int64_t)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl <= currentEpoch) {
        return YES;
    }
    return NO;
}

+ (instancetype)hostObjectWithHostRecord:(HttpdnsHostRecord *)hostRecord {
    HttpdnsHostObject *hostObject = [HttpdnsHostObject new];
    [hostObject setHostName:hostRecord.host];
    [hostObject setLastLookupTime:[hostRecord.createAt timeIntervalSince1970]];
    [hostObject setTTL:hostRecord.TTL];
    // 筛选IPv6地址
    NSMutableArray *allIps = [NSMutableArray arrayWithArray:hostRecord.IPs];
    NSMutableArray *ip6s = [NSMutableArray arrayWithCapacity:allIps.count];
    for (NSString *ip in allIps) {
        if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:ip]) {
            [ip6s addObject:ip];
        }
    }
    if (![EMASTools isValidArray:ip6s]) {
        hostObject.ips = [HttpdnsIpObject IPObjectsFromIPs:hostRecord.IPs];
    } else {
        [allIps removeObjectsInArray:ip6s];
        hostObject.ip6s = [HttpdnsIpObject IPObjectsFromIPs:ip6s];
        hostObject.ips = [HttpdnsIpObject IPObjectsFromIPs:allIps];
    }
    [hostObject setIsLoadFromDB:YES];
    return hostObject;
}

- (NSArray<NSString *> *)getIPStrings {
    NSArray<HttpdnsIpObject *> *IPRecords = [self getIps];
    NSMutableArray<NSString *> *IPs = [NSMutableArray array];
    for (HttpdnsIpObject *IPObject in IPRecords) {
        @try {
            [IPs addObject:IPObject.ip];
        } @catch (NSException *exception) {}
    }
    // 添加IPv6地址
    if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        NSArray<HttpdnsIpObject *> *IP6Records = [self getIp6s];
        for (HttpdnsIpObject *IPObject in IP6Records) {
            @try {
                [IPs addObject:IPObject.ip];
            } @catch (NSException *exception) {}
        }
    }
    return [IPs copy];
}

- (NSString *)description {
    if (![EMASTools isValidArray:_ip6s]) {
        return [NSString stringWithFormat:@"Host = %@ ips = %@ lastLookup = %lld ttl = %lld queryingState = %@",
                _hostName, _ips, _lastLookupTime, _ttl, _queryingState ? @"YES" : @"NO"];
    } else {
        return [NSString stringWithFormat:@"Host = %@ ips = %@ ip6s = %@ lastLookup = %lld ttl = %lld queryingState = %@",
                _hostName, _ips, _ip6s, _lastLookupTime, _ttl, _queryingState ? @"YES" : @"NO"];
    }
}

@end
