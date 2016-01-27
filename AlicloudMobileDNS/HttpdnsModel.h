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

@interface HttpdnsIpObject: NSObject<NSCoding>

@property (nonatomic, copy, getter=getIpString, setter=setIp:) NSString *ip;

@end


typedef NS_ENUM(NSInteger, HostState) {
    HttpdnsHostStateInitialized,
    HttpdnsHostStateQuerying,
    HttpdnsHostStateValid
};


@interface HttpdnsHostObject : NSObject<NSCoding>

@property (nonatomic, strong, setter=setHostName:, getter=getHostName) NSString *hostName;
@property (nonatomic, strong, setter=setIps:, getter=getIps) NSArray *ips;
@property (nonatomic, setter=setTTL:, getter=getTTL) long long ttl;
@property (nonatomic, getter=getLastLookupTime, setter=setLastLookupTime:) long long lastLookupTime;
@property (atomic, setter=setState:, getter=getState) HostState currentState;

-(instancetype)init;

-(BOOL)isExpired;

-(NSString *)description;

@end


@interface HttpdnsLocalCache : NSObject

+(void)writeToLocalCache:(NSDictionary *)allHostObjectsInManagerDict;

+(NSDictionary *)readFromLocalCache;

+(void)cleanLocalCache;

@end