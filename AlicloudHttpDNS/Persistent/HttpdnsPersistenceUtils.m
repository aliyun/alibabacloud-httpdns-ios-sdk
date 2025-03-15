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

#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsService.h"
#import "HttpdnsUtil.h"

static NSString *const ALICLOUD_HTTPDNS_ROOT_DIR_NAME = @"HTTPDNS";
static NSString *const ALICLOUD_HTTPDNS_HOST_CACHE_DIR_NAME = @"HostCache";

static dispatch_queue_t _fileCacheQueue = 0;

@implementation HttpdnsPersistenceUtils

#pragma mark - Base Path

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _fileCacheQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.fileCacheQueue", DISPATCH_QUEUE_SERIAL);
    });
}

#pragma mark - File Utils

+ (BOOL)saveJSON:(id)JSON toPath:(NSString *)path {
    if (![HttpdnsUtil isNotEmptyString:path]) {
        return NO;
    }
    BOOL isValid = [HttpdnsUtil isValidJSON:JSON];
    if (isValid) {
        __block BOOL saveSucceed = NO;
        @try {
            [self removeFile:path];
            dispatch_sync(_fileCacheQueue, ^{
                saveSucceed = [NSKeyedArchiver archiveRootObject:JSON toFile:path];
            });

        } @catch (NSException *exception) {}


        return saveSucceed;
    }
    return NO;
}

+ (id)getJSONFromPath:(NSString *)path {
    if (![HttpdnsUtil isNotEmptyString:path]) {
        return nil;
    }
    __block id JSON = nil;
    @try {
        dispatch_sync(_fileCacheQueue, ^{
            JSON = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
        });
        BOOL isValid = [HttpdnsUtil isValidJSON:JSON];

        if (isValid) {
            return JSON;
        }
    } @catch (NSException *exception) {
        //deal with the previous file version
        if ([[exception name] isEqualToString:NSInvalidArgumentException]) {
            JSON = [NSMutableDictionary dictionaryWithContentsOfFile:path];

            if (!JSON) {
                JSON = [NSMutableArray arrayWithContentsOfFile:path];
            }
        }
    }
    return JSON;
}

+ (BOOL)removeFile:(NSString *)path {
    if (![HttpdnsUtil isNotEmptyString:path]) {
        return NO;
    }
    __block NSError * error = nil;
    __block BOOL ret = NO;
    dispatch_sync(_fileCacheQueue, ^{
        ret = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    });
    return ret;
}

+ (void)createDirectoryIfNeeded:(NSString *)path {
    if (![HttpdnsUtil isNotEmptyString:path]) {
        return;
    }
    dispatch_sync(_fileCacheQueue, ^{
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:NULL];
        }
    });
}

#pragma mark - ~/Libraray/Private Documents

/// Base path, all paths depend it
+ (NSString *)homeDirectoryPath {
    return NSHomeDirectory();
}

// ~/Library
+ (NSString *)libraryDirectory {
    static NSString *path = nil;
    if (!path) {
        path = [[self homeDirectoryPath] stringByAppendingPathComponent:@"Library"];
    }
    return path;
}

// ~/Library/Private Documents/HTTPDNS
+ (NSString *)httpdnsDataDirectory {
    NSString *directory = [[HttpdnsPersistenceUtils libraryDirectory] stringByAppendingPathComponent:@"Private Documents/HTTPDNS"];
    [self createDirectoryIfNeeded:directory];
    return directory;
}

//Library/Private Documents/HTTPDNS/scheduleCenterResult
+ (NSString *)scheduleCenterResultDirectory {
    NSString *directory = [[HttpdnsPersistenceUtils httpdnsDataDirectory] stringByAppendingPathComponent:@"scheduleCenterResult"];
    [self createDirectoryIfNeeded:directory];
    return directory;
}

@end
