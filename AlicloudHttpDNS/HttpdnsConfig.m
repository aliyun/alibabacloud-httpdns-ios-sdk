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

#import "HttpdnsConfig.h"

const int HTTPDNS_MAX_REQUEST_RETRY_TIME = 1;

const int HTTPDNS_MAX_MANAGE_HOST_NUM = 100;

const int HTTPDNS_MAX_REQUEST_THREAD_NUM = 3;

const int HTTPDNS_MAX_KEEPALIVE_PERIOD_FOR_CACHED_HOST = 2 * 24 * 60 * 60;

const int HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL = 15;

const NSUInteger HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL = 10 * 60; /**< 10分钟 */

BOOL HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED = NO;

const int HTTPDNS_MAX_SCHEDULE_CENTER_REQUEST_RETRY_TIME = 2;
