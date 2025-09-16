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
#import "HttpdnsIPQualityDetector.h"


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
        IPObject.connectedRT = NSIntegerMax;
        [IPObjects addObject:IPObject];
    }
    return [IPObjects copy];
}

- (NSString *)description {
    if (self.connectedRT == NSIntegerMax) {
        return [NSString stringWithFormat:@"ip: %@", self.ip];
    } else {
        return [NSString stringWithFormat:@"ip: %@, connectedRT: %ld", self.ip, self.connectedRT];
    }
}

@end


@implementation HttpdnsHostObject

- (instancetype)init {
    _hostName = nil;
    _cacheKey = nil;
    _clientIp = nil;
    _v4ttl = -1;
    _lastIPv4LookupTime = 0;
    _v6ttl = -1;
    _lastIPv6LookupTime = 0;
    _isLoadFromDB = NO;
    _v4Ips = nil;
    _v6Ips = nil;
    _extra = nil;
    _hasNoIpv4Record = NO;
    _hasNoIpv6Record = NO;
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _cacheKey = [aDecoder decodeObjectForKey:@"cacheKey"];
        _hostName = [aDecoder decodeObjectForKey:@"hostName"];
        _clientIp = [aDecoder decodeObjectForKey:@"clientIp"];
        _v4Ips = [aDecoder decodeObjectForKey:@"v4ips"];
        _v4ttl = [aDecoder decodeInt64ForKey:@"v4ttl"];
        _lastIPv4LookupTime = [aDecoder decodeInt64ForKey:@"lastIPv4LookupTime"];
        _v6Ips = [aDecoder decodeObjectForKey:@"v6ips"];
        _v6ttl = [aDecoder decodeInt64ForKey:@"v6ttl"];
        _lastIPv6LookupTime = [aDecoder decodeInt64ForKey:@"lastIPv6LookupTime"];
        _extra = [aDecoder decodeObjectForKey:@"extra"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_cacheKey forKey:@"cacheKey"];
    [aCoder encodeObject:_hostName forKey:@"hostName"];
    [aCoder encodeObject:_clientIp forKey:@"clientIp"];
    [aCoder encodeObject:_v4Ips forKey:@"v4ips"];
    [aCoder encodeInt64:_v4ttl forKey:@"v4ttl"];
    [aCoder encodeInt64:_lastIPv4LookupTime forKey:@"lastIPv4LookupTime"];
    [aCoder encodeObject:_v6Ips forKey:@"v6ips"];
    [aCoder encodeInt64:_v6ttl forKey:@"v6ttl"];
    [aCoder encodeInt64:_lastIPv6LookupTime forKey:@"lastIPv6LookupTime"];
    [aCoder encodeObject:_extra forKey:@"extra"];
}

- (BOOL)isIpEmptyUnderQueryIpType:(HttpdnsQueryIPType)queryType {
    if (queryType & HttpdnsQueryIPTypeIpv4) {
        // 注意，_hasNoIpv4Record为true时，说明域名没有配置ipv4ip，不是需要去请求的情况
        if ([HttpdnsUtil isEmptyArray:[self getV4Ips]] && !_hasNoIpv4Record) {
            return YES;
        }

    } else if (queryType & HttpdnsQueryIPTypeIpv6 && !_hasNoIpv6Record) {
        // 注意，_hasNoIpv6Record为true时，说明域名没有配置ipv6ip，不是需要去请求的情况
        if ([HttpdnsUtil isEmptyArray:[self getV6Ips]] && !_hasNoIpv6Record) {
            return YES;
        }
    }
    return NO;
}

- (id)copyWithZone:(NSZone *)zone {
    HttpdnsHostObject *copy = [[[self class] allocWithZone:zone] init];
    if (copy) {
        copy.cacheKey = [self.cacheKey copyWithZone:zone];
        copy.hostName = [self.hostName copyWithZone:zone];
        copy.clientIp = [self.clientIp copyWithZone:zone];
        copy.v4Ips = [[NSArray allocWithZone:zone] initWithArray:self.v4Ips copyItems:YES];
        copy.v6Ips = [[NSArray allocWithZone:zone] initWithArray:self.v6Ips copyItems:YES];
        copy.v4ttl = self.v4ttl;
        copy.lastIPv4LookupTime = self.lastIPv4LookupTime;
        copy.v6ttl = self.v6ttl;
        copy.lastIPv6LookupTime = self.lastIPv6LookupTime;
        copy.hasNoIpv4Record = self.hasNoIpv4Record;
        copy.hasNoIpv6Record = self.hasNoIpv6Record;
        copy.extra = [self.extra copyWithZone:zone];
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

+ (instancetype)fromDBRecord:(HttpdnsHostRecord *)hostRecord {
    HttpdnsHostObject *hostObject = [HttpdnsHostObject new];
    [hostObject setCacheKey:hostRecord.cacheKey];
    [hostObject setHostName:hostRecord.hostName];
    [hostObject setClientIp:hostRecord.clientIp];
    NSArray *v4ips = hostRecord.v4ips;
    NSArray *v6ips = hostRecord.v6ips;
    if ([HttpdnsUtil isNotEmptyArray:v4ips]) {
        [hostObject setV4Ips:[HttpdnsIpObject IPObjectsFromIPs:v4ips]];
        [hostObject setV4TTL:hostRecord.v4ttl];
        [hostObject setLastIPv4LookupTime:hostRecord.v4LookupTime];

    }
    if ([HttpdnsUtil isNotEmptyArray:v6ips]) {
        [hostObject setV6Ips:[HttpdnsIpObject IPObjectsFromIPs:v6ips]];
        [hostObject setV6TTL:hostRecord.v6ttl];
        [hostObject setLastIPv6LookupTime:hostRecord.v6LookupTime];
    }
    [hostObject setExtra:hostRecord.extra];
    [hostObject setIsLoadFromDB:YES];
    return hostObject;
}

- (HttpdnsHostRecord *)toDBRecord {
    // 将IP对象数组转换为IP字符串数组
    NSArray<NSString *> *v4IpStrings = [self getV4IpStrings];
    NSArray<NSString *> *v6IpStrings = [self getV6IpStrings];

    // 创建当前时间作为modifyAt
    NSDate *currentDate = [NSDate date];

    // 使用hostName作为cacheKey，保持与fromDBRecord方法的一致性
    return [[HttpdnsHostRecord alloc] initWithId:0  // 数据库会自动分配ID
                                       cacheKey:self.cacheKey
                                       hostName:self.hostName
                                       createAt:currentDate
                                       modifyAt:currentDate
                                       clientIp:self.clientIp
                                       v4ips:v4IpStrings
                                       v4ttl:self.v4ttl
                                       v4LookupTime:self.lastIPv4LookupTime
                                       v6ips:v6IpStrings
                                       v6ttl:self.v6ttl
                                       v6LookupTime:self.lastIPv6LookupTime
                                       extra:self.extra];
}

- (NSArray<NSString *> *)getV4IpStrings {
    NSArray<HttpdnsIpObject *> *ipv4Records = [self getV4Ips];
    NSMutableArray<NSString *> *ipv4Strings = [NSMutableArray arrayWithCapacity:ipv4Records.count];
    for (HttpdnsIpObject *IPObject in ipv4Records) {
        [ipv4Strings addObject:[IPObject getIpString]];
    }
    return [ipv4Strings copy];
}

- (NSArray<NSString *> *)getV6IpStrings {
    NSArray<HttpdnsIpObject *> *ipv6Records = [self getV6Ips];
    NSMutableArray<NSString *> *ipv6sString = [NSMutableArray arrayWithCapacity:ipv6Records.count];
    for (HttpdnsIpObject *ipObject in ipv6Records) {
        [ipv6sString addObject:[ipObject getIpString]];
    }
    return [ipv6sString copy];
}

- (void)updateConnectedRT:(NSInteger)connectedRT forIP:(NSString *)ip {
    if ([HttpdnsUtil isEmptyString:ip]) {
        return;
    }

    BOOL isIPv6 = [HttpdnsUtil isIPv6Address:ip];

    NSArray<HttpdnsIpObject *> *ipObjects = isIPv6 ? [self getV6Ips] : [self getV4Ips];
    if ([HttpdnsUtil isEmptyArray:ipObjects]) {
        return;
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
        return;
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
        [self setV6Ips:[mutableIpObjects copy]];
    } else {
        [self setV4Ips:[mutableIpObjects copy]];
    }
}

- (NSString *)description {
    if (![HttpdnsUtil isNotEmptyArray:_v6Ips]) {
        return [NSString stringWithFormat:@"Host = %@ v4ips = %@ v4ttl = %lld v4LastLookup = %lld extra = %@",
                _hostName, _v4Ips, _v4ttl, _lastIPv4LookupTime, _extra];
    } else {
        return [NSString stringWithFormat:@"Host = %@ v4ips = %@ v4ttl = %lld v4LastLookup = %lld v6ips = %@ v6ttl = %lld v6LastLookup = %lld extra = %@",
                _hostName, _v4Ips, _v4ttl, _lastIPv4LookupTime, _v6Ips, _v6ttl, _lastIPv6LookupTime, _extra];
    }
}

@end
