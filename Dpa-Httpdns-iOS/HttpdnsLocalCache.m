//
//  HttpdnsLocalCache.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/2/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsLocalCache.h"

static NSString *localCacheKey = @"httpdns_hostManagerData";
@implementation HttpdnsLocalCache

+(void)writeToLocalCache:(NSMutableDictionary *)allHostObjectInManagerDict inQueue:(dispatch_queue_t)syncQueue {
    dispatch_sync(syncQueue, ^{
        NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
        [userDefault setObject:allHostObjectInManagerDict forKey:localCacheKey];
        [userDefault synchronize];
    });
}

+(NSDictionary *)readFromLocalCache {
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    return [userDefault dictionaryForKey:localCacheKey];
}
@end