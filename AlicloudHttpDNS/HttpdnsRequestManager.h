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

//V6版本默认只保留一个IP

FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_VALID_SERVER_CERTIFICATE_IP;

@class HttpdnsHostObject;

@interface HttpdnsRequestManager : NSObject

- (instancetype)initWithAccountId:(NSInteger)accountId;

- (void)setExpiredIPEnabled:(BOOL)enable;

- (void)setCachedIPEnabled:(BOOL)enable discardRecordsHasExpiredFor:(NSTimeInterval)duration;

- (void)setDegradeToLocalDNSEnabled:(BOOL)enable;

- (void)setPreResolveAfterNetworkChanged:(BOOL)enable;

- (void)preResolveHosts:(NSArray *)hosts queryType:(HttpdnsQueryIPType)queryType;

- (HttpdnsHostObject *)resolveHost:(HttpdnsRequest *)request;

// 内部缓存开关，不触发加载DB到内存的操作
- (void)setPersistentCacheIpEnabled:(BOOL)enable;

- (void)cleanMemoryAndPersistentCacheOfHostArray:(NSArray<NSString *> *)hostArray;

- (void)cleanMemoryAndPersistentCacheOfAllHosts;


#pragma mark - Expose to Testcases

- (HttpdnsHostObject *)mergeLookupResultToManager:(HttpdnsHostObject *)result host:host cacheKey:(NSString *)cacheKey underQueryIpType:(HttpdnsQueryIPType)queryIpType;

- (HttpdnsHostObject *)executeRequest:(HttpdnsRequest *)request retryCount:(int)hasRetryedCount;

- (NSString *)showMemoryCache;

- (void)cleanAllHostMemoryCache;

- (void)syncReloadCacheFromDbToMemory;

@end
