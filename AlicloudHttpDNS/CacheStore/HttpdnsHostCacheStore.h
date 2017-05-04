//
//  HttpdnsHostCacheStore.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsCacheStore.h"

@class HttpdnsHostRecord;

@interface HttpdnsHostCacheStore : HttpdnsCacheStore

- (void)insertHostRecords:(NSArray<HttpdnsHostRecord *> *)HostRecords;

- (void)deleteHostRecord:(HttpdnsHostRecord *)HostRecord;

- (void)deleteHostRecordForHost:(NSString *)host;

- (NSArray<HttpdnsHostRecord *> *)hostRecordsForHosts:(NSArray<NSString *> *)hosts;

@end
