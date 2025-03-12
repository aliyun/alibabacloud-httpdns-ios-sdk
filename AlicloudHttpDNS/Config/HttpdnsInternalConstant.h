//
// HttpdnsInternalConstant.h
// AlicloudHttpDNS
//
//  Created by xuyecan on 2025/03/10.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#ifndef httpdns_internal_constant_h
#define httpdns_internal_constant_h

#define HTTPDNS_MAX_REQUEST_RETRY_TIME 1

#define HTTPDNS_MAX_MANAGE_HOST_NUM 100

#define HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL 3

#define HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL (10 * 60)

// 在iOS14和iOS16，网络信息的获取权限受到越来越紧的限制
// 除非用户主动声明需要相关entitlement，不然只能拿到空信息
// 考虑大多数用户并不会申请这些权限，我们放弃针对细节的网络信息做缓存粒度隔离
// 出于兼容性考虑，网络运营商只有default一种类型
#define HTTPDNS_DEFAULT_NETWORK_CARRIER_NAME @"default"

#endif
