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
FOUNDATION_EXTERN NSArray *ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST_IPV6;

@interface HttpdnsScheduleCenter : NSObject

@property (nonatomic, copy, readonly) NSDictionary *scheduleCenterResult;

@property (nonatomic, assign, getter=doHaveNewIPList, readonly) BOOL haveNewIPList;

//服务IPv4 list
@property (nonatomic, copy, readonly) NSArray *IPList;

//服务IPv6 list
@property (nonatomic, copy, readonly) NSArray *IPv6List;


@property (nonatomic, assign) NSInteger activatedServerIPIndex;

//默认0开始
@property (nonatomic, assign) NSInteger activatedServerIPv6Index;


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

/*
 * 立即进行服务IP的更新，不受时间限制，谨慎使用，目前提供给region切换场景下使用
 */
- (void)forceUpdateIpListAsyncImmediately;



/// 获取当前index 的ipv4 服务IP
/// @param index 数组索引
- (NSString *)getActivatedServerIPWithIndex:(NSInteger)index;

/// 获取当前 的ipv6 服务IP 索引自动计算
- (NSString *)getActivatedServerIPv6WithAuto;


- (NSInteger)nextServerIPIndexFromIPIndex:(NSInteger)IPIndex increase:(NSInteger)increase;

- (void)changeToNextServerIPIndexFromIPIndex:(NSInteger)IPIndex;

/// 返回当前服务IP region
- (NSString *)getServiceIPRegion;

@end
