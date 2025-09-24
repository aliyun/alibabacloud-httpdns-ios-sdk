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

@class HttpDnsService;

@class HttpdnsHostObject;

@interface HttpdnsUtil : NSObject

+ (BOOL)isIPv4Address:(NSString *)addr;

+ (BOOL)isIPv6Address:(NSString *)addr;

+ (BOOL)isAnIP:(NSString *)candidate;

+ (BOOL)isAHost:(NSString *)host;

+ (void)warnMainThreadIfNecessary;

+ (NSDictionary *)getValidDictionaryFromJson:(id)jsonValue;

+ (BOOL)isEmptyArray:(NSArray *)inputArr;

+ (BOOL)isNotEmptyArray:(NSArray *)inputArr;

+ (BOOL)isEmptyString:(NSString *)inputStr;

+ (BOOL)isNotEmptyString:(NSString *)inputStr;

+ (BOOL)isValidJSON:(id)JSON;

+ (BOOL)isEmptyDictionary:(NSDictionary *)inputDict;

+ (BOOL)isNotEmptyDictionary:(NSDictionary *)inputDict;

+ (NSArray *)joinArrays:(NSArray *)array1 withArray:(NSArray *)array2;

+ (NSString *)getMD5StringFrom:(NSString *)originString;

+ (NSString *)URLEncodedString:(NSString *)str;

+ (NSString *)generateSessionID;

+ (NSString *)generateUserAgent;

+ (NSData *)encryptDataAESCBC:(NSData *)plaintext
                      withKey:(NSData *)key
                        error:(NSError **)error;

+ (NSData *)decryptDataAESCBC:(NSData *)ciphertext
                      withKey:(NSData *)key
                        error:(NSError **)error;

+ (NSString *)hexStringFromData:(NSData *)data;

+ (NSData *)dataFromHexString:(NSString *)hexString;

+ (NSString *)hmacSha256:(NSString *)data key:(NSString *)key;

+ (void)processCustomTTL:(HttpdnsHostObject *)hostObject forHost:(NSString *)host;
+ (void)processCustomTTL:(HttpdnsHostObject *)hostObject forHost:(NSString *)host service:(HttpDnsService *)service;

@end
