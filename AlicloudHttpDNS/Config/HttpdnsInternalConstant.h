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

const int HTTPDNS_MAX_REQUEST_RETRY_TIME = 1;

const int HTTPDNS_MAX_MANAGE_HOST_NUM = 100;

const int HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL = 3;

const NSUInteger HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL = 10 * 60;

// 在iOS14和iOS16，网络信息的获取权限受到越来越紧的限制
// 除非用户主动声明需要相关entitlement，不然只能拿到空信息
// 考虑大多数用户并不会申请这些权限，我们放弃针对细节的网络信息做缓存粒度隔离
// 出于兼容性考虑，网络运营商只有default一种类型
const NSString * const HTTPDNS_DEFAULT_NETWORK_CARRIER_NAME = @"default";
