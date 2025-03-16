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

#import "HttpdnsService.h"
#import "HttpdnsRequestManager.h"
#import "HttpdnsLog_Internal.h"


@interface HttpDnsService()

@property (nonatomic, strong) HttpdnsRequestManager *requestManager;

@property (nonatomic, assign) NSTimeInterval authTimeOffset;

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *IPRankingDataSource;

@property (nonatomic, assign) NSTimeInterval timeoutInterval;

@property (nonatomic, assign) BOOL enableHttpsRequest;

@property (nonatomic, assign) BOOL hasAllowedArbitraryLoadsInATS;

- (NSString *)getIpByHost:(NSString *)host;

- (NSArray *)getIpsByHost:(NSString *)host;

- (NSString *)getIpByHostInURLFormat:(NSString *)host;

- (NSDictionary<NSString *, NSNumber *> *)getIPRankingDatasource;

@end

