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
#import "HttpdnsRequest.h"

@class HttpdnsHostRecord;
@class HttpdnsIPRecord;
@class HttpdnsServerIpObject;


@interface HttpdnsIpObject: NSObject<NSCoding, NSCopying>

@property (nonatomic, copy, getter=getIpString, setter=setIp:) NSString *ip;
@property (nonatomic, assign) NSInteger connectedRT;

@end


@interface HttpdnsHostObject : NSObject<NSCoding, NSCopying>

@property (nonatomic, copy, setter=setCacheKey:, getter=getCacheKey) NSString *cacheKey;
@property (nonatomic, copy, setter=setHostName:, getter=getHostName) NSString *hostName;

@property (nonatomic, copy, setter=setClientIp:, getter=getClientIp) NSString *clientIp;

@property (nonatomic, strong, setter=setV4Ips:, getter=getV4Ips) NSArray<HttpdnsIpObject *> *v4Ips;
@property (nonatomic, strong, setter=setV6Ips:, getter=getV6Ips) NSArray<HttpdnsIpObject *> *v6Ips;

// 虽然当前后端接口的设计里ttl并没有区分v4、v6，但原则是应该要分开
// v4 ttl
@property (nonatomic, setter=setV4TTL:, getter=getV4TTL) int64_t v4ttl;
@property (nonatomic, assign) int64_t lastIPv4LookupTime;

// v6 ttl
@property (nonatomic, setter=setV6TTL:, getter=getV6TTL) int64_t v6ttl;
@property (nonatomic, assign) int64_t lastIPv6LookupTime;

// 用来标记该域名为配置v4记录或v6记录的情况，避免如双栈网络下因为某个协议查不到record需要重复请求
// 这个信息不用持久化，一次APP启动周期内使用是合适的
@property (nonatomic, assign) BOOL hasNoIpv4Record;
@property (nonatomic, assign) BOOL hasNoIpv6Record;

@property (nonatomic, strong, setter=setExtra:, getter=getExtra) NSString *extra;

// 标识是否从持久化缓存加载
@property (nonatomic, assign, setter=setIsLoadFromDB:, getter=isLoadFromDB) BOOL isLoadFromDB;

- (instancetype)init;

- (BOOL)isIpEmptyUnderQueryIpType:(HttpdnsQueryIPType)queryType;

- (BOOL)isExpiredUnderQueryIpType:(HttpdnsQueryIPType)queryIPType;

+ (instancetype)fromDBRecord:(HttpdnsHostRecord *)IPRecord;

/**
 * 将当前对象转换为数据库记录对象
 * @return 数据库记录对象
 */
- (HttpdnsHostRecord *)toDBRecord;

- (NSArray<NSString *> *)getV4IpStrings;

- (NSArray<NSString *> *)getV6IpStrings;

/**
 * 更新指定IP的connectedRT值并重新排序IP列表
 * @param ip 需要更新的IP地址
 * @param connectedRT 检测到的RT值，-1表示不可达
 */
- (void)updateConnectedRT:(NSInteger)connectedRT forIP:(NSString *)ip;

@end
