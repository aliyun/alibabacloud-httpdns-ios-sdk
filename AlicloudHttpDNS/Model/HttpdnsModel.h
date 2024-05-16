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

#import <Foundation/Foundation.h>
#import "HttpdnsIPv6Manager.h"

@class HttpdnsHostRecord;
@class HttpdnsIPRecord;
@class HttpdnsServerIpObject;



@interface HttpdnsIpObject: NSObject<NSCoding>

@property (nonatomic, copy, getter=getIpString, setter=setIp:) NSString *ip;

@end

@interface HttpdnsHostObject : NSObject<NSCoding>

@property (nonatomic, strong, setter=setHostName:, getter=getHostName) NSString *hostName;
@property (nonatomic, strong, setter=setIps:, getter=getIps) NSArray<HttpdnsIpObject *> *ips;
@property (nonatomic, strong, setter=setIp6s:, getter=getIp6s) NSArray<HttpdnsIpObject *> *ip6s;
@property (nonatomic, setter=setTTL:, getter=getTTL) int64_t ttl;
//v4 ttl
@property (nonatomic, setter=setV4TTL:, getter=getV4TTL) int64_t v4ttl;
@property (nonatomic, assign) int64_t lastIPv4LookupTime;

//v6 ttl
@property (nonatomic, setter=setV6TTL:, getter=getV6TTL) int64_t v6ttl;
@property (nonatomic, assign) int64_t lastIPv6LookupTime;

//region 当次解析时，服务IP设置的region ,为空或者nil 默认是国内场景
@property (nonatomic, copy) NSString *ipRegion;
@property (nonatomic, copy) NSString *ip6Region;


@property (nonatomic, strong, setter=setExtra:, getter=getExtra) NSDictionary *extra;

// 标识是否从持久化缓存加载
@property (nonatomic, assign, setter=setIsLoadFromDB:, getter=isLoadFromDB) BOOL isLoadFromDB;

// 查询成功后的本地时间戳
@property (nonatomic, getter=getLastLookupTime, setter=setLastLookupTime:) int64_t lastLookupTime;

- (instancetype)init;

- (BOOL)isIpEmptyUnderQueryIpType:(HttpdnsQueryIPType)queryType;

- (BOOL)isExpiredUnderQueryIpType:(HttpdnsQueryIPType)queryIPType;

- (BOOL)isRegionNotMatch:(NSString *)region underQueryIpType:(HttpdnsQueryIPType)queryType;

+ (instancetype)hostObjectWithHostRecord:(HttpdnsHostRecord *)IPRecord;

- (NSArray<NSString *> *)getIPStrings;

- (NSArray<NSString *> *)getIP6Strings;

@end

