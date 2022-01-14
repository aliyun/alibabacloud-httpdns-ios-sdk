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

@interface HttpdnsRequestTestHelper : NSObject

+ (void)zeroSnifferTimeForTest;

@end

/**
 * Disable状态开始30秒后可以进行“嗅探”行为
 */
static NSTimeInterval ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 0;

@interface HttpdnsRequestScheduler ()

- (void)setServerDisable:(BOOL)serverDisable host:(NSString *)host;

- (void)setServerDisable:(BOOL)serverDisable host:(NSString *)host activatedServerIPIndex:(NSInteger)activatedServerIPIndex;

- (BOOL)isServerDisable;

@property (nonatomic, strong) HttpdnsRequestTestHelper *testHelper;
@property (nonatomic, assign) BOOL IPRankingEnabled;

//内部缓存开关，不触发加载DB到内存的操作
- (void)_setCachedIPEnabled:(BOOL)enable;
- (BOOL)_getCachedIPEnabled;

//设置开启region
- (void)_setRegin:(NSString *)region;

+ (void)configureServerIPsAndResetActivatedIPTime;

- (void)canNotResolveHost:(NSString *)host error:(NSError *)error isRetry:(BOOL)isRetry activatedServerIPIndex:(NSInteger)activatedServerIPIndex;

+ (dispatch_queue_t)hostCacheQueue;

- (void)loadIPsFromCacheSyncIfNeeded;

- (void)cleanAllHostMemoryCache;

- (void)cleanCacheWithHostArray:(NSArray <NSString *>*)hostArray;

@end

