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

static NSTimeInterval ALICLOUD_HTTPDNS_HOST_CACHE_MAX_CACHE_AGE = 0;

@interface HttpdnsHostCacheStore : HttpdnsCacheStore

- (void)insertHostRecords:(NSArray<HttpdnsHostRecord *> *)hostRecords;

//- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHosts:(NSArray<NSString *> *)hosts;

- (NSArray<NSNumber *> *)hostRecordIdsForHost:(NSString *)host;

- (NSArray<HttpdnsHostRecord *> *)hostRecordsForCurrentCarrier;
- (NSArray<HttpdnsHostRecord *> *)hostRecordsForCarrier:(NSString *)carrier;

- (HttpdnsHostRecord *)hostRecordsWithCurrentCarrierForHost:(NSString *)host;

- (HttpdnsHostRecord *)hostRecordsForHost:(NSString *)host carrier:(NSString *)carrier;

- (void)cleanAllExpiredHostRecordsSync;

- (void)deleteHostRecordAndItsIPsWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs;

// for test
- (void)deleteHostRecordAndItsIPsWithHost:(NSString *)host;
- (NSString *)showDBCache;

@end
