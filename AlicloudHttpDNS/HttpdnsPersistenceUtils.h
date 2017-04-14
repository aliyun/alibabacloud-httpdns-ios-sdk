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

@interface HttpdnsPersistenceUtils : NSObject

+ (NSString *)disableStatusPath;
+ (NSString *)activatedIPIndexPath;
+ (NSString *)scheduleCenterResultPath;
+ (NSString *)needFetchFromScheduleCenterStatusPatch;

+ (NSTimeInterval)timeSinceCreateForPath:(NSString *)patch;
+ (BOOL)saveJSON:(id)JSON toPath:(NSString *)path;
+ (id)getJSONFromDirectory:(NSString *)directory fileName:(NSString *)fileName;
+ (id)getJSONFromDirectory:(NSString *)directory fileName:(NSString *)fileName timeout:(NSTimeInterval)timeoutInterval;

+(BOOL)removeFile:(NSString *)path;
+(BOOL)fileExist:(NSString *)path;
+(BOOL)createFile:(NSString *)path;

/*!
 * 请勿直接使用文件名调用该接口，应该使用文件所在文件夹
 */
+ (BOOL)deleteFilesInDirectory:(NSString *)dirPath moreThanDays:(NSInteger)numberOfDays;
+ (BOOL)deleteFilesInDirectory:(NSString *)dirPath moreThanHours:(NSInteger)numberOfHours;
+ (BOOL)deleteFilesInDirectory:(NSString *)dirPath moreThanTimeInterval:(NSTimeInterval)timeInterval;

@end
