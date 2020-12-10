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
#import "HttpdnsModel.h"
#import "HttpdnsIPv6Manager.h"

FOUNDATION_EXTERN NSInteger const ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE;
FOUNDATION_EXTERN NSInteger const ALICLOUD_HTTPDNS_HTTP_COMMON_ERROR_CODE;
FOUNDATION_EXTERN NSInteger const ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE;
FOUNDATION_EXTERN NSInteger const ALICLOUD_HTTPDNS_HTTP_STREAM_READ_ERROR_CODE;
FOUNDATION_EXTERN NSInteger const ALICLOUD_HTTPDNS_HTTPS_TIMEOUT_ERROR_CODE;
FOUNDATION_EXTERN NSInteger const ALICLOUD_HTTPDNS_HTTP_CANNOT_CONNECT_SERVER_ERROR_CODE;
FOUNDATION_EXTERN NSInteger const ALICLOUD_HTTPDNS_HTTP_USER_LEVEL_CHANGED_ERROR_CODE;

FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_KEY;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_CACHE_FILE_NAME;

@interface HttpdnsRequest : NSObject

- (HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error;

- (HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error activatedServerIPIndex:(NSInteger)activatedServerIPIndex queryIPType:(HttpdnsQueryIPType)queryIPType;

@end
