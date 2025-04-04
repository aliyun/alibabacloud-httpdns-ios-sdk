//
// HttpdnsInternalConstant.h
// AlicloudHttpDNS
//
//  Created by xuyecan on 2025/03/10.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#ifndef HTTPDNS_INTERNAL_CONSTANT_H
#define HTTPDNS_INTERNAL_CONSTANT_H

static const int HTTPDNS_MAX_REQUEST_RETRY_TIME = 1;

static const int HTTPDNS_MAX_MANAGE_HOST_NUM = 100;

static const int HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL = 3;

static const NSUInteger HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL = 10 * 60;

// 在iOS14和iOS16，网络信息的获取权限受到越来越紧的限制
// 除非用户主动声明需要相关entitlement，不然只能拿到空信息
// 考虑大多数用户并不会申请这些权限，我们放弃针对细节的网络信息做缓存粒度隔离
// 出于兼容性考虑，网络运营商只有default一种类型
#define HTTPDNS_DEFAULT_NETWORK_CARRIER_NAME @"default"

// 调度地址示例：http://106.11.90.200/sc/httpdns_config?account_id=153519&platform=ios&sdk_version=1.6.1
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST = @"httpdns-sc.aliyuncs.com";

static NSString *const ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY = @"ErrorMessage";

static NSString *const kAlicloudHttpdnsRegionConfigV4HostKey = @"service_ip";
static NSString *const kAlicloudHttpdnsRegionConfigV6HostKey = @"service_ipv6";

static NSString *const kAlicloudHttpdnsRegionKey = @"HttpdnsRegion";

#define SECONDS_OF_ONE_YEAR 365 * 24 * 60 * 60

static NSString *const ALICLOUD_HTTPDNS_ERROR_DOMAIN = @"HttpdnsErrorDomain";

static NSInteger const ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE = 10003;
static NSInteger const ALICLOUD_HTTPDNS_HTTP_COMMON_ERROR_CODE = 10004;

static NSInteger const ALICLOUD_HTTPDNS_HTTPS_TIMEOUT_ERROR_CODE = 10005;
static NSInteger const ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE = 10006;
static NSInteger const ALICLOUD_HTTPDNS_HTTP_OPEN_STREAM_ERROR_CODE = 10007;
static NSInteger const ALICLOUD_HTTPDNS_HTTPS_NO_DATA_ERROR_CODE = 10008;

static NSInteger const ALICLOUD_HTTP_UNSUPPORTED_STATUS_CODE = 10013;
static NSInteger const ALICLOUD_HTTP_PARSE_JSON_FAILED = 10014;

// 加密错误码
static NSInteger const ALICLOUD_HTTPDNS_ENCRYPT_INVALID_PARAMS_ERROR_CODE = 10021;
static NSInteger const ALICLOUD_HTTPDNS_ENCRYPT_RANDOM_IV_ERROR_CODE = 10022;
static NSInteger const ALICLOUD_HTTPDNS_ENCRYPT_FAILED_ERROR_CODE = 10023;

#endif
