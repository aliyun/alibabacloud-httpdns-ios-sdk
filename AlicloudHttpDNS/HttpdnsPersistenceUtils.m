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

static NSString *const ALICLOUD_HTTPDNS_ROOT_DIR_NAME = @"HTTPDNS";

@implementation HttpdnsPersistenceUtils

#pragma mark - Base Path

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
    if ([JSON isKindOfClass:[NSDictionary class]] || [JSON isKindOfClass:[NSArray class]]) {
        return [NSKeyedArchiver archiveRootObject:JSON toFile:path];
    }
    
    return NO;
}

+ (id)getJSONFromPath:(NSString *)path {
    id JSON = nil;
    @try {
        JSON = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
        
        if ([JSON isMemberOfClass:[NSDictionary class]] || [JSON isMemberOfClass:[NSArray class]]) {
            return JSON;
        }
    }
    @catch (NSException *exception) {
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
    NSError * error = nil;
    BOOL ret = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    return ret;
}

+ (BOOL)fileExist:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (BOOL)createFile:(NSString *)path {
    BOOL ret = [[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:nil];
    return ret;
}

+ (void)createDirectoryIfNeeded:(NSString *)path {
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
    
    NSDate *nowDate = [NSDate date];
    NSFileManager *fileMgr = [[NSFileManager alloc] init];
    NSError *error = nil;
    NSArray *directoryContents = [fileMgr contentsOfDirectoryAtPath:dirPath error:&error];
    if (error == nil) {
        for (NSString *path in directoryContents) {
            NSString *fullPath = [dirPath stringByAppendingPathComponent:path];
            NSDate *lastModified = [HttpdnsPersistenceUtils lastModified:fullPath];
            NSTimeInterval timeSinceCreate = [nowDate timeIntervalSinceDate:lastModified];
            if (timeSinceCreate < timeInterval)
                continue;
            
            BOOL removeSuccess = [fileMgr removeItemAtPath:fullPath error:&error];
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

// assume the file is exist
+ (NSDate *)lastModified:(NSString *)fullPath {
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:NULL];
    return [fileAttributes fileModificationDate];
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

@end
