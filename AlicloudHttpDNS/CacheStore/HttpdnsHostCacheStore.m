//
//  HttpdnsHostCacheStore.m
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsHostCacheStore.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsgetNetworkInfoHelper.h"

@implementation HttpdnsHostCacheStore

- (void)insertHostRecords:(NSArray<HttpdnsHostRecord *> *)HostRecords {
    /** 当前网络运营商名字，或者wifi名字 */
    NSString *networkName = [HttpdnsgetNetworkInfoHelper getNetworkName];
}

- (void)deleteHostRecord:(HttpdnsHostRecord *)HostRecord {
    
}

- (void)deleteHostRecordForHost:(NSString *)host {
    
}

- (NSArray<HttpdnsHostRecord *> *)hostRecordsForHosts:(NSArray<NSString *> *)hosts {
    return nil;
}

@end
