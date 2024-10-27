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

// 调度地址示例：http://106.11.90.200/sc/httpdns_config?account_id=153519&platform=ios&sdk_version=1.6.1
static NSString *const HTTPDNS_BEACON_APPKEY  = @"24657847";
static NSString *const HTTPDNS_BEACON_APPSECRECT = @"f30fc0937f2b1e9e50a1b7134f1ddb10";

 static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST = @"httpdns-sc.aliyuncs.com";

static NSString *const ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY = @"ErrorMessage";

static NSString *const kAlicloudHttpdnsRegionConfigV4HostKey = @"service_ip";
static NSString *const kAlicloudHttpdnsRegionConfigV6HostKey = @"service_ipv6";

static NSString *const kAlicloudHttpdnsRegionKey = @"HttpdnsRegion";

#define SECONDS_OF_ONE_YEAR 365 * 24 * 60 * 60

//当前时间戳，单位秒
#define ALICLOUD_HTTPDNS_DISTANT_CURRENT_TIMESTAMP \
    ([[NSDate date] timeIntervalSince1970])

static NSString *const ALICLOUD_HTTPDNS_ERROR_DOMAIN = @"HttpdnsErrorDomain";

NSInteger const ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE = 10003;
NSInteger const ALICLOUD_HTTPDNS_HTTP_COMMON_ERROR_CODE = 10004;

NSInteger const ALICLOUD_HTTPDNS_HTTPS_TIMEOUT_ERROR_CODE = 10005;
NSInteger const ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE = 10006;

NSInteger const ALICLOUD_HTTPDNS_HTTP_STREAM_READ_ERROR_CODE = 10007;
NSInteger const ALICLOUD_HTTPDNS_HTTP_CANNOT_CONNECT_SERVER_ERROR_CODE = 10008;

NSInteger const ALICLOUD_HTTP_UNSUPPORTED_STATUS_CODE = 10013;
NSInteger const ALICLOUD_HTTP_PARSE_JSON_FAILED = 10014;

#endif /* HttpdnsConstants_h */
