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

#ifndef HttpdnsConstants_h
#define HttpdnsConstants_h

#import <Foundation/Foundation.h>

static NSString *const HTTPDNS_IOS_SDK_VERSION = @"3.0.2";


// 调度地址示例：http://106.11.90.200/sc/httpdns_config?account_id=153519&platform=ios&sdk_version=1.6.1

static NSString *const HTTPDNS_BEACON_APPKEY  = @"24657847";
static NSString *const HTTPDNS_BEACON_APPSECRECT = @"f30fc0937f2b1e9e50a1b7134f1ddb10";

/**
 HTTPDNS 国际版 标识
 1: 默认设置region 为sg
 2: 调度IP 只用于调度 ，服务IP 只用于解析
 3: 内置 调度IP 和 服务IP 和通用版不同
 4: 其他策略基本保持一致
 */
static BOOL const HTTPDNS_INTER = false;

// ipv6 only 场景下 调度 服务ip 的策略
// true: ipv6 only 场景下 调度、服务ip 走ipv4 合成ipv6 方式;
// false: ipv6 only 场景下 调度、服务ip 采用对应的调度、服务的ipv6地址;
static BOOL const HTTPDNS_IPV6_SYNTHESIZED_FROM_IPV4 = false;


#pragma mark - Schedule Center
///=============================================================================
/// @name Schedule Center
///=============================================================================

 static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST = @"httpdns-sc.aliyuncs.com";

///===================================国内版本==========================================
//国内版内置调度IPv4地址
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP = @"203.107.1.97";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP_2 = @"203.107.1.100";
//国内版内置调度IPv6地址
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IPV6 = @"2401:b180:2000:20::10";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IPV6_2 = @"2401:b180:2000:30::1c";


//国内内置服务IPv4地址
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_SERVER_HOST_IP = @"203.107.1.1";
//国内内置服务IPv6地址
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_SERVER_HOST_IPV6 = @"2401:b180:2000:30::1c";
///===================================国内版本==========================================


///===================================国际版本版本==========================================
//国际版内置调度IPv4地址
static NSString *const ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_REQUEST_HOST_IP = @"8.219.58.10";
static NSString *const ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_REQUEST_HOST_IP_2 = @"8.219.89.41";
static NSString *const ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_REQUEST_HOST_IP_3 = @"203.107.1.97"; //用于兜底
//国际版内置调度IPv6地址
static NSString *const ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_REQUEST_HOST_IPV6 = @"240b:4000:f10::92";
static NSString *const ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_REQUEST_HOST_IPV6_2 = @"240b:4000:f10::208";


//国际内置服务IPv4地址
static NSString *const ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_SERVER_HOST_IP = @"161.117.200.122";
//国际内置服务IPv6地址
static NSString *const ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_SERVER_HOST_IPV6 = @"240b:4000:f10::178";
///===================================国际版本版本==========================================


//初次安装启动 默认的内置服务ipv4 地址
static NSString *const ALICLOUD_HTTPDNS_SERVER_IP_DEFAULT = HTTPDNS_INTER ? ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_SERVER_HOST_IP : ALICLOUD_HTTPDNS_SCHEDULE_CENTER_SERVER_HOST_IP;
//初次安装启动 默认的内置服务ipv6 地址
static NSString *const ALICLOUD_HTTPDNS_SERVER_IPV6_DEFAULT = HTTPDNS_INTER ? ALICLOUD_HTTPDNS_INTER_SCHEDULE_CENTER_SERVER_HOST_IPV6 : ALICLOUD_HTTPDNS_SCHEDULE_CENTER_SERVER_HOST_IPV6;

//static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_PATH = @"sc/httpdns_config";
static NSString *const ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY = @"ErrorMessage";
static NSString *const ALICLOUD_HTTPDNS_ERROR_SERVICE_LEVEL_DENY = @"ServiceLevelDeny";

//requst paramer

//account_id	必须	HTTPDNS的Account ID
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_PARAMER_ACCOUNT_ID_KEY = @"account_id";

//platform	必须	平台信息：android或ios，字母小写
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_PARAMER_PLATFORM_KEY = @"platform";

//sdk_version	必须	SDK本身的版本号
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_PARAMER_VERSION_KEY = @"sdk_version";

//app_name
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_PARAMER_APP_KEY = @"app_name";  /**< bundle id */

//ipv4 key
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_IP_KEY = @"service_ip";
//ipv6 key
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_IPV6_KEY = @"service_ipv6";

static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_REGION_KEY = @"service_region";  //服务IP对应的region

static NSString *const ALICLOUD_HTTPDNS_REGION_KEY = @"HttpdnsRegion";


//当前时间戳，单位秒
#define ALICLOUD_HTTPDNS_DISTANT_CURRENT_TIMESTAMP \
    ([[NSDate date] timeIntervalSince1970])

//单位秒
#define ALICLOUD_HTTPDNS_DISTANT_FUTURE_TIMESTAMP \
    ([[NSDate distantFuture] timeIntervalSince1970])

#define ALICLOUD_HTTPDNS_VALID_TIMESTAMP(timestamp) ({      \
    int64_t timestamp_ = (int64_t)(timestamp);  \
    if (timestamp_ <= 0) timestamp_ = ALICLOUD_HTTPDNS_DISTANT_FUTURE_TIMESTAMP;  \
    timestamp_;  \
})

#endif /* HttpdnsConstants_h */
