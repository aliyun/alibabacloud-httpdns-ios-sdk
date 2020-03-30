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

/*!
 * API 文档：http://gitlab.alibaba-inc.com/alicloud-ams/httpdns-doc/blob/master/v6/sc-proto.md
 */

//http://106.11.90.200/sc/httpdns_config?account_id=153519&platform=ios&sdk_version=1.6.1

static NSString *const HTTPDNS_BEACON_APPKEY  = @"24657847";
static NSString *const HTTPDNS_BEACON_APPSECRECT = @"f30fc0937f2b1e9e50a1b7134f1ddb10";

#pragma mark - Schedule Center
///=============================================================================
/// @name Schedule Center
///=============================================================================

// static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST = @"httpdns-sc.aliyuncs.com";
// 我的修改 CENTER_REQUEST_HOST_IP
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP = @"203.107.1.97";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP_2 = @"203.107.1.100";
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

//requst result

//SCHEDULE_CENTER configure
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_KEY = @"service_status";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_IP_KEY = @"service_ip";

//"service_status": "enable"
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_ENABLE_VALUE = @"enable";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_DISABLE_VALUE = @"disable";

static NSString *const ALICLOUD_HTTPDNS_BEACON_REQUEST_PARAM_ACCOUNTID = @"accountId";
static NSString *const ALICLOUD_HTTPDNS_BEACON_STATUS_KEY = @"status";
static NSString *const ALICLOUD_HTTPDNS_BEACON_SDK_DISABLE = @"disabled";

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
