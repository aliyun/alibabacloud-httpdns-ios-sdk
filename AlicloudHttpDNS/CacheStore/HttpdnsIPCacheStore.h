//
//  HttpdnsIPCacheStore.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsCacheStore.h"

@class HttpdnsIPRecord;

@interface HttpdnsIPCacheStore : HttpdnsCacheStore

+ (instancetype)sharedInstance;

- (void)insertIPs:(NSArray<NSString *> *)IPs hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL ipRegion:(NSString *)ipRegion;
- (void)insertIP6s:(NSArray<NSString *> *)IPs hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL ip6Region:(NSString *)ip6Region;

- (void)deleteIPRecordWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs;
- (void)deleteIP6RecordWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs;


/// 清空ipv4数据
- (void)cleanIPRecord;
/// 清空ipv6数据
- (void)cleanIP6Record;


- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHostID:(NSUInteger)hostID;
- (NSArray<HttpdnsIPRecord *> *)IP6RecordsForHostID:(NSUInteger)hostID;
- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHostID:(NSUInteger)hostID db:(HttpdnsDatabase *)db;
- (NSArray<HttpdnsIPRecord *> *)IP6RecordsForHostID:(NSUInteger)hostID db:(HttpdnsDatabase *)db;
- (id)init NS_UNAVAILABLE;

@end
