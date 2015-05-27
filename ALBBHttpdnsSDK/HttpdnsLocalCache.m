//
//  HttpdnsLocalCache.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/2/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsLocalCache.h"
#import "HttpdnsLog.h"
#import "HttpdnsUtil.h"

static NSString *localCacheKey = @"httpdns_hostManagerData";
static long long lastWroteToCacheTime = 0;
static long long mimimalIntervalInSecond = 10;
@implementation HttpdnsLocalCache

+(void)writeToLocalCache:(NSDictionary *)allHostObjectInManagerDict {
    long long currentTime = [HttpdnsUtil currentEpochTimeInSecond];
    // 如果离上次写缓存时间小于阈值，放弃此次写入
    if (currentTime - lastWroteToCacheTime < mimimalIntervalInSecond) {
        HttpdnsLogDebug(@"[writeToLocalCache] - Write too often, abort this writing");
        return;
    }
    lastWroteToCacheTime = currentTime;
    NSData *buffer = [NSKeyedArchiver archivedDataWithRootObject:allHostObjectInManagerDict];
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    [userDefault setObject:buffer forKey:localCacheKey];
    [userDefault synchronize];
    HttpdnsLogDebug(@"[writeToLocalCache] - write %lu to local file system", [allHostObjectInManagerDict count]);
}

+(NSDictionary *)readFromLocalCache {
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    NSData *buffer = [userDefault objectForKey:localCacheKey];
    NSDictionary *dict = [NSKeyedUnarchiver unarchiveObjectWithData:buffer];
    HttpdnsLogDebug(@"[readFromLocalCache] - read %lu from local file system", [dict count]);
    return dict;
}

+(void)cleanLocalCache {
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    [userDefault removeObjectForKey:localCacheKey];
}
@end