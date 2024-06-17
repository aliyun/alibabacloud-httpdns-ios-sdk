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

#import "HttpdnsRequestScheduler.h"

FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_1;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_2;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_3;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_4;

static NSTimeInterval intervalBeforeAllowToSniffAfterLastServerDisable;

@interface HttpdnsRequestScheduler ()

// ip探测优选开关 两者需要同时满足
// 这个ip探测优选开关是走的beacon服务
@property (nonatomic, assign) BOOL IPRankingEnabled;


- (void)setServerDisable:(BOOL)serverDisable;

- (BOOL)isServerDisable;

+ (void)setZeroSnifferTimeInterval;

- (NSString *)showMemoryCache;

- (HttpdnsHostObject *)mergeLookupResultToManager:(HttpdnsHostObject *)result host:host cacheKey:(NSString *)cacheKey underQueryIpType:(HttpdnsQueryIPType)queryIpType;

- (HttpdnsHostObject *)executeRequest:(HttpdnsRequest *)request
                           retryCount:(int)hasRetryedCount
                                error:(NSError *)error;

// 内部缓存开关，不触发加载DB到内存的操作
- (void)setPersistentCacheIpEnabled:(BOOL)enable;
- (BOOL)getPersistentCacheIpEnabled;

+ (void)configureServerIPsAndResetActivatedIPTime;

- (void)syncReloadCacheFromDbToMemoryByIspCarrier;

- (void)cleanAllHostMemoryCache;

- (void)cleanMemoryAndPersistentCacheOfHostArray:(NSArray <NSString *>*)hostArray;

- (void)cleanMemoryAndPersistentCacheOfAllHosts;

@end

