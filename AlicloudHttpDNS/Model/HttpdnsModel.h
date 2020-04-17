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
@property (nonatomic, strong, setter=setExtra:, getter=getExtra) NSDictionary *extra;

// 标识是否从持久化缓存加载
@property (nonatomic, assign, setter=setIsLoadFromDB:, getter=getIsLoadFromDB) BOOL isLoadFromDB;

/*!
 * 查询成功后的本地时间戳
 */
@property (nonatomic, getter=getLastLookupTime, setter=setLastLookupTime:) int64_t lastLookupTime;
@property (atomic, setter=setQueryingState:, getter=isQuerying) BOOL queryingState;

- (instancetype)init;

- (BOOL)isExpired;

+ (instancetype)hostObjectWithHostRecord:(HttpdnsHostRecord *)IPRecord;

- (NSArray<NSString *> *)getIPStrings;

- (NSArray<NSString *> *)getIP6Strings;

@end

