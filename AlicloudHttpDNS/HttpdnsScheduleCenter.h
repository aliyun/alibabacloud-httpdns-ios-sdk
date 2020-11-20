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

FOUNDATION_EXTERN NSInteger ALICLOUD_HTTPDNS_RESET_IP_LIST_TIME_DAY;
FOUNDATION_EXTERN NSArray *ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST;

@interface HttpdnsScheduleCenter : NSObject

/*!
 * 停服
 */
@property (nonatomic, assign, getter=isStopService, readonly) BOOL stopService;

@property (nonatomic, copy, readonly) NSDictionary *scheduleCenterResult;

@property (nonatomic, assign, getter=doHaveNewIPList, readonly) BOOL haveNewIPList;

@property (nonatomic, copy, readonly) NSArray *IPList;

@property (nonatomic, assign) NSInteger activatedServerIPIndex;

@property (nonatomic, assign, getter=isConnectingWithScheduleCenter) BOOL connectingWithScheduleCenter;

+ (instancetype)sharedInstance;

/*!
 * 在App启动后进行一次更新，一天只更新一次
 */
- (void)upateIPListIfNeededAsync;

/*!
 * 在当前IP池中最后一个IP超时后，进行一次更新。无次数限制。
 */
- (void)forceUpdateIpListAsync;

- (NSString *)getActivatedServerIPWithIndex:(NSInteger)index;

- (NSInteger)nextServerIPIndexFromIPIndex:(NSInteger)IPIndex increase:(NSInteger)increase;

- (void)changeToNextServerIPIndexFromIPIndex:(NSInteger)IPIndex;

- (void)setSDKDisableFromBeacon;
- (void)clearSDKDisableFromBeacon;

@end
