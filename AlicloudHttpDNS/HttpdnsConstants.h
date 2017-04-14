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

//http://106.11.90.200/sc/httpdns_config?account_id=153519&platform=ios&sdk_version=1.5.0

#pragma mark - Schedule Center
///=============================================================================
/// @name Schedule Center
///=============================================================================

static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST = @"httpdns-sc.aliyuncs.com";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP = @"203.107.1.97";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP_2 = @"203.107.1.100";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_PATH = @"sc/httpdns_config";

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
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_KEY = @"service";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_IP_KEY = @"service_ip";

//"service": "enable"
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_ENABLE_VALUE = @"enable";
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_DISABLE_VALUE = @"disable";

#endif /* HttpdnsConstants_h */
