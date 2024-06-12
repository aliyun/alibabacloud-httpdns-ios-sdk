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

#import "HttpdnsScheduleCenter.h"

static NSTimeInterval ALICLOUD_HTTPDNS_NEED_FETCH_IP_LIST_STATUS_CACHE_TIMEOUT_INTERVAL = 24 * 60 * 60;
static NSTimeInterval ALICLOUD_HTTPDNS_ABLE_TO_CONNECT_SCHEDULE_CENTER_INTERVAL = 5 * 60;

typedef void (^HttpDnsIdCallback)(NSDictionary *result);

@interface HttpdnsScheduleCenterTestHelper : NSObject

+ (void)shortAutoConnectToScheduleCenterInterval;

/*!
 *   放在HttpdnsScheduleCenter初始化之后：
 */
+ (void)shortMixConnectToScheduleCenterInterval;

+ (void)zeroAutoConnectToScheduleCenterInterval;

+ (void)zeroMixConnectToScheduleCenterInterval;

+ (void)setFirstIPWrongForTest;

+ (void)setFirstTwoWrongForScheduleCenterIPs;

+ (void)setAllWrongForScheduleCenterIPs;

@end

@interface HttpdnsScheduleCenter ()

@property (nonatomic, copy) NSString *scheduleCenterResultPath;

@property (nonatomic, copy) NSArray *IPList;

@property (nonatomic, copy) NSArray *IPv6List;

- (void)setScheduleCenterResult:(NSDictionary *)scheduleCenterResult;

- (void)forceUpdateIpListAsyncWithCallback:(HttpDnsIdCallback)callback;

@property (nonatomic, strong) HttpdnsScheduleCenterTestHelper *scheduleCenterTestHelper;

@end

