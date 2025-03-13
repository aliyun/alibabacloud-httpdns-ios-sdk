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

#import "HttpdnsHostObject.h"
#import "HttpdnsInternalConstant.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsIPRecord.h"
#import "HttpdnsIPQualityDetector.h"
#import "HttpdnsIpv6Adapter.h"


@implementation HttpdnsIpObject

- (instancetype)init {
    if (self = [super init]) {
        // 初始化connectedRT为最大整数值
        self.connectedRT = NSIntegerMax;
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        self.ip = [aDecoder decodeObjectForKey:@"ip"];
        self.connectedRT = [aDecoder decodeIntegerForKey:@"connectedRT"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.ip forKey:@"ip"];
    [aCoder encodeInteger:self.connectedRT forKey:@"connectedRT"];
}

- (id)copyWithZone:(NSZone *)zone {
    HttpdnsIpObject *copy = [[[self class] allocWithZone:zone] init];
    if (copy) {
        copy.ip = [self.ip copyWithZone:zone];
        copy.connectedRT = self.connectedRT;
    }
    return copy;
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
    return [NSString stringWithFormat:@"ip: %@", self.ip];
}

@end


@implementation HttpdnsHostObject

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
    _extra = nil;
    _hasNoIpv4Record = NO;
    _hasNoIpv6Record = NO;
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
        _extra = [aDecoder decodeObjectForKey:@"extra"];
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
    [aCoder encodeObject:_hostName forKey:@"extra"];
}

- (BOOL)isIpEmptyUnderQueryIpType:(HttpdnsQueryIPType)queryType {
    if (queryType & HttpdnsQueryIPTypeIpv4) {
        // 注意，_hasNoIpv4Record为true时，说明域名没有配置ipv4ip，不是需要去请求的情况
        if ([HttpdnsUtil isEmptyArray:[self getIps]] && !_hasNoIpv4Record) {
            return YES;
        }

    } else if (queryType & HttpdnsQueryIPTypeIpv6 && !_hasNoIpv6Record) {
        // 注意，_hasNoIpv6Record为true时，说明域名没有配置ipv6ip，不是需要去请求的情况
        if ([HttpdnsUtil isEmptyArray:[self getIp6s]] && !_hasNoIpv6Record) {
            return YES;
        }
    }
    return NO;
}

- (id)copyWithZone:(NSZone *)zone {
    HttpdnsHostObject *copy = [[[self class] allocWithZone:zone] init];
    if (copy) {
        copy.hostName = [self.hostName copyWithZone:zone];
        copy.ips = [[NSArray allocWithZone:zone] initWithArray:self.ips copyItems:YES];
        copy.ip6s = [[NSArray allocWithZone:zone] initWithArray:self.ip6s copyItems:YES];
        copy.ttl = self.ttl;
        copy.lastLookupTime = self.lastLookupTime;
        copy.v4ttl = self.v4ttl;
        copy.lastIPv4LookupTime = self.lastIPv4LookupTime;
        copy.v6ttl = self.v6ttl;
        copy.lastIPv6LookupTime = self.lastIPv6LookupTime;
        copy.hasNoIpv4Record = self.hasNoIpv4Record;
        copy.hasNoIpv6Record = self.hasNoIpv6Record;
        copy.extra = [[NSDictionary allocWithZone:zone] initWithDictionary:self.extra copyItems:YES];
        copy.isLoadFromDB = self.isLoadFromDB;
    }
    return copy;
}

- (BOOL)isExpiredUnderQueryIpType:(HttpdnsQueryIPType)queryIPType {
    int64_t currentEpoch = (int64_t)[[[NSDate alloc] init] timeIntervalSince1970];
    if ((queryIPType & HttpdnsQueryIPTypeIpv4)
        && !_hasNoIpv4Record
        && _lastIPv4LookupTime + _v4ttl <= currentEpoch) {
        return YES;
    }
    if ((queryIPType & HttpdnsQueryIPTypeIpv6)
        && !_hasNoIpv6Record
        && _lastIPv6LookupTime + _v6ttl <= currentEpoch) {
        return YES;
    }
    return NO;
}

+ (instancetype)hostObjectWithHostRecord:(HttpdnsHostRecord *)hostRecord {
    HttpdnsHostObject *hostObject = [HttpdnsHostObject new];
    // 这里从db取出的hostRecord的host字段实际上是cacheKey，因为历史问题，数据库未设计单独的cacheKey字段
    [hostObject setHostName:hostRecord.host];
    [hostObject setLastLookupTime:[hostRecord.createAt timeIntervalSince1970]];
    [hostObject setTTL:hostRecord.TTL];
    [hostObject setExtra:hostRecord.extra];
    NSArray *ips = hostRecord.IPs;
    NSArray *ip6s = hostRecord.IP6s;
    if ([HttpdnsUtil isNotEmptyArray:ips]) {
        hostObject.ips = [HttpdnsIpObject IPObjectsFromIPs:ips];

        //设置ipv4 的ttl lookuptimer
        [hostObject setV4TTL:hostRecord.TTL];
        [hostObject setLastIPv4LookupTime:hostObject.getLastLookupTime];

    }
    if ([HttpdnsUtil isNotEmptyArray:ip6s]) {
        hostObject.ip6s = [HttpdnsIpObject IPObjectsFromIPs:ip6s];

        //设置ipv6 的ttl lookuptimer
        [hostObject setV6TTL:hostRecord.TTL];
        [hostObject setLastIPv6LookupTime:hostObject.getLastLookupTime];

    }
    [hostObject setIsLoadFromDB:YES];
    return hostObject;
}

- (NSArray<NSString *> *)getIP4Strings {
    NSArray<HttpdnsIpObject *> *ipRecords = [self getIps];
    NSMutableArray<NSString *> *ips = [NSMutableArray arrayWithCapacity:ipRecords.count];
    for (HttpdnsIpObject *IPObject in ipRecords) {
        [HttpdnsUtil safeAddObject:IPObject.ip toArray:ips];
    }
    return [ips copy];
}

- (NSArray<NSString *> *)getIP6Strings {
    NSArray<HttpdnsIpObject *> *ip6Records = [self getIp6s];
    NSMutableArray<NSString *> *ips = [NSMutableArray arrayWithCapacity:ip6Records.count];
    if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        for (HttpdnsIpObject *ipObject in ip6Records) {
            [HttpdnsUtil safeAddObject:ipObject.ip toArray:ips];
        }
    }
    return [ips copy];
}

- (BOOL)updateConnectedRT:(NSInteger)connectedRT forIP:(NSString *)ip {
    if ([HttpdnsUtil isEmptyString:ip]) {
        return NO;
    }

    BOOL isIPv6 = [HttpdnsIPv6Adapter isIPv6Address:ip];

    NSArray<HttpdnsIpObject *> *ipObjects = isIPv6 ? [self getIp6s] : [self getIps];
    if ([HttpdnsUtil isEmptyArray:ipObjects]) {
        return NO;
    }

    // 查找匹配的IP对象并更新connectedRT
    BOOL found = NO;
    NSMutableArray<HttpdnsIpObject *> *mutableIpObjects = [ipObjects mutableCopy];

    for (HttpdnsIpObject *ipObject in ipObjects) {
        if ([ipObject.ip isEqualToString:ip]) {
            ipObject.connectedRT = connectedRT;
            found = YES;
            break;
        }
    }

    if (!found) {
        return NO;
    }

    // 根据connectedRT值对IP列表进行排序，-1值放在最后
    [mutableIpObjects sortUsingComparator:^NSComparisonResult(HttpdnsIpObject *obj1, HttpdnsIpObject *obj2) {
        // 如果obj1的connectedRT为-1，将其排在后面
        if (obj1.connectedRT == -1) {
            return NSOrderedDescending;
        }
        // 如果obj2的connectedRT为-1，将其排在后面
        if (obj2.connectedRT == -1) {
            return NSOrderedAscending;
        }
        // 否则按照connectedRT值从小到大排序
        return obj1.connectedRT > obj2.connectedRT ? NSOrderedDescending : (obj1.connectedRT < obj2.connectedRT ? NSOrderedAscending : NSOrderedSame);
    }];

    // 更新排序后的IP列表
    if (isIPv6) {
        [self setIp6s:[mutableIpObjects copy]];
    } else {
        [self setIps:[mutableIpObjects copy]];
    }

    return YES;
}

- (NSString *)description {
    if (![HttpdnsUtil isNotEmptyArray:_ip6s]) {
        return [NSString stringWithFormat:@"Host = %@ ips = %@ lastLookup = %lld ttl = %lld extra = %@",
                _hostName, _ips, _lastLookupTime, _ttl, _extra];
    } else {
        return [NSString stringWithFormat:@"Host = %@ ips = %@ ip6s = %@ lastLookup = %lld ttl = %lld extra = %@",
                _hostName, _ips, _ip6s, _lastLookupTime, _ttl, _extra];
    }
}

@end
