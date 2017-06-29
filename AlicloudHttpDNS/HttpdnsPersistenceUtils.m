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
#import "HttpdnsServiceProvider.h"
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

/// Base path, all paths depend it
+ (NSString *)homeDirectoryPath {
    return NSHomeDirectory();
}

#pragma mark - ~/Documents

// ~/Documents
+ (NSString *)appDocumentPath {
    static NSString *path = nil;
    
    if (!path) {
        path = [[self homeDirectoryPath] stringByAppendingPathComponent:@"Documents"];
    }
    
    return path;
}

// ~/Documents/HTTPDNS
+ (NSString *)HttpDnsDocumentPath {
    NSString *path = [self appDocumentPath];
    
    path = [path stringByAppendingPathComponent:ALICLOUD_HTTPDNS_ROOT_DIR_NAME];
    
    [self createDirectoryIfNeeded:path];
    
    return path;
}

// ~/Documents/HTTPDNS/keyvalue
+ (NSString *)keyValueDatabasePath {
    return [[self HttpDnsDocumentPath] stringByAppendingPathComponent:@"keyvalue"];
}

// ~/Library/Caches/HTTPDNS/HostCache
+ (NSString *)hostCachePatch {
    NSString *path = [self appCachePath];
    
    path = [path stringByAppendingPathComponent:ALICLOUD_HTTPDNS_ROOT_DIR_NAME];
    path = [path stringByAppendingPathComponent:ALICLOUD_HTTPDNS_HOST_CACHE_DIR_NAME];
    
    [self createDirectoryIfNeeded:path];
    
    return path;
}

// ~/Library/Caches/HTTPDNS/HostCache/databaseName
+ (NSString *)hostCacheDatabasePathWithName:(NSString *)name {
    if (name) {
        return [[self hostCachePatch] stringByAppendingPathComponent:name];
    }
    
    return nil;
}

#pragma mark - ~/Library/Caches

// ~/Library/Caches
+ (NSString *)appCachePath {
    static NSString *path = nil;
    
    if (!path) {
        path = [[self homeDirectoryPath] stringByAppendingPathComponent:@"Library"];
        path = [path stringByAppendingPathComponent:@"Caches"];
    }
    
    return path;
}

#pragma mark - ~/Libraray/Private Documents

// ~/Library
+ (NSString *)libraryDirectory {
    static NSString *path = nil;
    if (!path) {
        path = [[self homeDirectoryPath] stringByAppendingPathComponent:@"Library"];
    }
    return path;
}

#pragma mark - File Utils

+ (BOOL)saveJSON:(id)JSON toPath:(NSString *)path {
    if (![HttpdnsUtil isValidString:path]) {
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
    if (![HttpdnsUtil isValidString:path]) {
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

+ (id)getJSONFromDirectory:(NSString *)directory fileName:(NSString *)fileName {
    NSString *fullPath = [directory stringByAppendingPathComponent:fileName];
    BOOL isfileExist = [HttpdnsPersistenceUtils fileExist:fullPath];
    if (!isfileExist) {
        return nil;
    }
    return [self getJSONFromPath:fullPath];
}

+ (id)getJSONFromDirectory:(NSString *)directory fileName:(NSString *)fileName timeout:(NSTimeInterval)timeoutInterval {
    [HttpdnsPersistenceUtils deleteFilesInDirectory:directory moreThanTimeInterval:timeoutInterval];
    return [self getJSONFromDirectory:directory fileName:fileName];
}

+ (BOOL)removeFile:(NSString *)path {
    if (![HttpdnsUtil isValidString:path]) {
        return NO;
    }
    __block NSError * error = nil;
    __block BOOL ret = NO;
    dispatch_sync(_fileCacheQueue, ^{
        ret = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    });
    return ret;
}

+ (BOOL)fileExist:(NSString *)path {
    if (![HttpdnsUtil isValidString:path]) {
        return NO;
    }
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (BOOL)createFile:(NSString *)path {
    if (![HttpdnsUtil isValidString:path]) {
        return NO;
    }
    BOOL ret = [[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:nil];
    return ret;
}

+ (void)createDirectoryIfNeeded:(NSString *)path {
    if (![HttpdnsUtil isValidString:path]) {
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
    }
}

+ (BOOL)deleteFilesInDirectory:(NSString *)dirPath moreThanDays:(NSInteger)numberOfDays {
    return [self deleteFilesInDirectory:dirPath moreThanTimeInterval:(numberOfDays * 24 * 3600)];
}

+ (BOOL)deleteFilesInDirectory:(NSString *)dirPath moreThanHours:(NSInteger)numberOfHours {
    return [self deleteFilesInDirectory:dirPath moreThanTimeInterval:(numberOfHours * 3600)];
}

+ (BOOL)deleteFilesInDirectory:(NSString *)dirPath moreThanTimeInterval:(NSTimeInterval)timeInterval {
    BOOL success = NO;
    
    NSFileManager *fileMgr = [[NSFileManager alloc] init];
    __block NSError *error = nil;
    NSArray *directoryContents = [fileMgr contentsOfDirectoryAtPath:dirPath error:&error];
    if (error == nil) {
        for (NSString *path in directoryContents) {
            NSString *fullPath = [dirPath stringByAppendingPathComponent:path];
            NSTimeInterval timeSinceCreate = [self timeSinceCreateForPath:fullPath];
            if (timeSinceCreate < timeInterval)
                continue;
            __block BOOL removeSuccess = NO;
            dispatch_sync(_fileCacheQueue, ^{
                removeSuccess = [fileMgr removeItemAtPath:fullPath error:&error];
            });
            if (!removeSuccess) {
                // NSLog(@"remove error happened");
                success = NO;
            }
        }
    } else {
        // NSLog(@"remove error happened");
        success = NO;
    }
    
    return success;
}

+ (NSDate *)lastModified:(NSString *)fullPath {
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:NULL];
   NSDate *lastModified = [fileAttributes fileModificationDate];
    // assume the file is exist
    if (!lastModified) {
        lastModified = [NSDate distantFuture];
    }
    return lastModified;
}

+ (NSTimeInterval)timeSinceCreateForPath:(NSString *)patch {
    NSDate *nowDate = [NSDate date];
    NSDate *lastModified = [self lastModified:patch];
    NSTimeInterval timeSinceCreate = [nowDate timeIntervalSinceDate:lastModified];
    return timeSinceCreate;
}

#pragma mark -  Private Documents Concrete Path

// ~/Library/Private Documents/HTTPDNS
+ (NSString *)privateDocumentsDirectory {
    NSString *ret = [[HttpdnsPersistenceUtils libraryDirectory] stringByAppendingPathComponent:@"Private Documents/HTTPDNS"];
    [self createDirectoryIfNeeded:ret];
    return ret;
}

+ (NSString *)disableStatusPath {
    NSString *ret = [[HttpdnsPersistenceUtils privateDocumentsDirectory] stringByAppendingPathComponent:@"disableStatus"];
    [self createDirectoryIfNeeded:ret];
    return ret;
}

+ (NSString *)activatedIPIndexPath {
    NSString *ret = [[HttpdnsPersistenceUtils privateDocumentsDirectory] stringByAppendingPathComponent:@"activatedIPIndex"];
    [self createDirectoryIfNeeded:ret];
    return ret;
}

+ (NSString *)scheduleCenterResultPath {
    NSString *ret = [[HttpdnsPersistenceUtils privateDocumentsDirectory] stringByAppendingPathComponent:@"scheduleCenterResult"];
    [self createDirectoryIfNeeded:ret];
    return ret;
}

+ (NSString *)needFetchFromScheduleCenterStatusPatch {
    NSString *ret = [[HttpdnsPersistenceUtils privateDocumentsDirectory] stringByAppendingPathComponent:@"needFetchFromScheduleCenterStatus"];
    [self createDirectoryIfNeeded:ret];
    return ret;
}

@end
