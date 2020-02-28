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

@property (nonatomic, copy) NSString *host;

+ (instancetype)sharedInstance;

- (void)insertIPs:(NSArray<NSString *> *)IPs hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL;
- (void)insertIP6s:(NSArray<NSString *> *)IPs hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL;

- (void)deleteIPRecordWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs;
- (void)deleteIP6RecordWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs;

- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHostID:(NSUInteger)hostID;
- (NSArray<HttpdnsIPRecord *> *)IP6RecordsForHostID:(NSUInteger)hostID;
- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHostID:(NSUInteger)hostID db:(HttpdnsDatabase *)db;
- (NSArray<HttpdnsIPRecord *> *)IP6RecordsForHostID:(NSUInteger)hostID db:(HttpdnsDatabase *)db;
- (id)init NS_UNAVAILABLE;

@end
