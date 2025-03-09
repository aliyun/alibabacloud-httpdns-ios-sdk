//
//  HttpdnsHostCacheStore.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsCacheStore.h"

@class HttpdnsHostRecord;
@class HttpdnsIPRecord;

@interface HttpdnsHostCacheStore : HttpdnsCacheStore

+ (instancetype)sharedInstance;

- (void)insertHostRecords:(NSArray<HttpdnsHostRecord *> *)hostRecords;

- (NSArray<NSNumber *> *)getHostRecordIdsForHost:(NSString *)host;

- (NSArray<HttpdnsHostRecord *> *)getAllHostRecords;

- (HttpdnsHostRecord *)getHostRecordsForHost:(NSString *)host;

- (void)cleanHostRecordsAlreadyExpiredAt:(NSTimeInterval)specifiedTime;

- (void)deleteHostRecordAndItsIPsWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs;

- (void)deleteHostRecordAndItsIPsWithHost:(NSString *)host;


/// 清空指定host的数据库数据 包括(HostRecord + ipv4 + ipv6 三张表的数据)
- (void)cleanDbOfHosts:(NSArray <NSString *>*)hostArray;

- (void)cleanDbOfAllHosts;

// only for testcase
- (NSString *)showDBCache;

@end
