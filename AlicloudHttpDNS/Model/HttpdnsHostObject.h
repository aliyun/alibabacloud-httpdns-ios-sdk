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


@interface HttpdnsIpObject: NSObject<NSCoding, NSCopying>

@property (nonatomic, copy, getter=getIpString, setter=setIp:) NSString *ip;
@property (nonatomic, assign) NSInteger connectedRT;

@end


@interface HttpdnsHostObject : NSObject<NSCoding, NSCopying>

@property (nonatomic, copy, setter=setHostName:, getter=getHostName) NSString *hostName;
@property (nonatomic, strong, setter=setIps:, getter=getIps) NSArray<HttpdnsIpObject *> *ips;
@property (nonatomic, strong, setter=setIp6s:, getter=getIp6s) NSArray<HttpdnsIpObject *> *ip6s;

// ttl，httpdns最早的接口设计里，不区分v4、v6解析结果的ttl
@property (nonatomic, setter=setTTL:, getter=getTTL) int64_t ttl;
@property (nonatomic, getter=getLastLookupTime, setter=setLastLookupTime:) int64_t lastLookupTime;

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

@property (nonatomic, strong, setter=setExtra:, getter=getExtra) NSDictionary *extra;

// 标识是否从持久化缓存加载
@property (nonatomic, assign, setter=setIsLoadFromDB:, getter=isLoadFromDB) BOOL isLoadFromDB;

- (instancetype)init;

- (BOOL)isIpEmptyUnderQueryIpType:(HttpdnsQueryIPType)queryType;

- (BOOL)isExpiredUnderQueryIpType:(HttpdnsQueryIPType)queryIPType;

+ (instancetype)hostObjectWithHostRecord:(HttpdnsHostRecord *)IPRecord;

- (NSArray<NSString *> *)getIP4Strings;

- (NSArray<NSString *> *)getIP6Strings;

/**
 * 更新指定IP的connectedRT值并重新排序IP列表
 * @param ip 需要更新的IP地址
 * @param connectedRT 检测到的RT值，-1表示不可达
 * @return 是否成功更新
 */
- (BOOL)updateConnectedRT:(NSInteger)connectedRT forIP:(NSString *)ip;

@end
