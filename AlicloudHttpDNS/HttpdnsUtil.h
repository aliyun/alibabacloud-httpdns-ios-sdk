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

@interface HttpdnsUtil : NSObject

+ (int64_t)currentEpochTimeInSecond;

+ (NSString *)currentEpochTimeInSecondString;

+ (BOOL)isAnIP:(NSString *)candidate;

+ (BOOL)isAHost:(NSString *)host;

/*!
 * host 或者 IPv4环境下直接返回，IPv6环境下做兼容处理。
 */
+ (NSString *)getRequestHostFromString:(NSString *)string;

+ (void)warnMainThreadIfNecessary;

//wifi是否可用
+ (BOOL)isWifiEnable;

//蜂窝移动网络是否可用
+ (BOOL)isCarrierConnectEnable;

+ (BOOL)isAbleToRequest;

+ (NSDictionary *)getValidDictionaryFromJson:(id)jsonValue;

+ (id)convertJsonStringToObject:(NSString *)jsonStr;

+ (BOOL)isValidArray:(id)notValidArray;

+ (BOOL)isValidString:(id)notValidString;

+ (BOOL)isValidJSON:(id)JSON;

+ (BOOL)isValidDictionary:(id)obj;

+ (NSString *)getMD5StringFrom:(NSString *)originString;

+ (NSError *)getErrorFromError:(NSError *)error statusCode:(NSInteger)statusCode json:(NSDictionary *)json isHTTPS:(BOOL)isHTTPS;

+ (NSString *)generateSessionID;

@end
