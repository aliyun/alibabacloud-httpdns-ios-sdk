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

FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_1;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_2;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_3;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_SERVER_IP_4;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_HTTP_SERVER_PORT;
FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT;

FOUNDATION_EXTERN NSArray *ALICLOUD_HTTPDNS_SERVER_IP_LIST;
FOUNDATION_EXTERN NSInteger ALICLOUD_HTTPDNS_RESET_ACTIVATED_SERVER_IP_TIME_HOURS;

@class HttpdnsHostObject;

@interface HttpdnsRequestScheduler : NSObject

- (void)addPreResolveHosts:(NSArray *)hosts;

- (HttpdnsHostObject *)addSingleHostAndLookup:(NSString *)host synchronously:(BOOL)sync;

- (void)setExpiredIPEnabled:(BOOL)enable;

- (void)setPreResolveAfterNetworkChanged:(BOOL)enable;

- (void)changeToNextServerIPIfNeededWithError:(NSError *)error
                                  fromIPIndex:(NSInteger)IPIndex
                                      isHTTPS:(BOOL)isHTTPS;

- (NSString *)getActivatedServerIPWithIndex:(NSInteger)index;

@end
