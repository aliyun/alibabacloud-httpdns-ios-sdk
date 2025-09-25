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

@interface HttpdnsScheduleCenter : NSObject

/// 针对多账号场景的调度中心构造方法
/// 注意：若无需多账号隔离，可继续使用 sharedInstance
- (instancetype)initWithAccountId:(NSInteger)accountId;

- (void)initRegion:(NSString *)region;

- (void)resetRegion:(NSString *)region;

- (void)asyncUpdateRegionScheduleConfig;

- (void)rotateServiceServerHost;

- (NSString *)currentActiveServiceServerV4Host;

- (NSString *)currentActiveServiceServerV6Host;


#pragma mark - Expose to Testcases

- (void)asyncUpdateRegionScheduleConfigAtRetry:(int)retryCount;

- (NSString *)getActiveUpdateServerHost;

- (NSArray<NSString *> *)currentUpdateServerV4HostList;

- (NSArray<NSString *> *)currentServiceServerV4HostList;

- (NSArray<NSString *> *)currentUpdateServerV6HostList;

- (NSArray<NSString *> *)currentServiceServerV6HostList;

- (int)currentActiveUpdateServerHostIndex;

- (int)currentActiveServiceServerHostIndex;

@end
