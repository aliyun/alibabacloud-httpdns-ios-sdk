//
//  HttpdnsIPCacheStore.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsIPCacheStore.h"
#import "HttpdnsIPRecord.h"
#import "HttpdnsIPCacheStoreSQL.h"
#import "HttpdnsUtil.h"

@implementation HttpdnsIPCacheStore

- (void)databaseQueueDidLoad {
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        [db executeUpdate:ALICLOUD_HTTPDNS_SQL_CREATE_IP_RECORD_TABLE];
    }));
    
    [self migrateDatabaseIfNeeded:self.databaseQueue.path];
}

- (void)migrateDatabaseIfNeeded:(NSString *)databasePath {
    //后续数据库升级，兼容操作
}

- (void)insertIPs:(NSArray<NSString *> *)IPs hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL {
    [HttpdnsUtil warnMainThreadIfNecessary];
    if (!IPs || IPs.count == 0) {
        return;
    }
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        for (NSString *IP in IPs) {
            NSArray *insertionRecord = [self insertionRecordForIP:IP hostRecordId:hostRecordId TTL:TTL];
            [db executeUpdate:ALICLOUD_HTTPDNS_SQL_INSERT_IP_RECORD withArgumentsInArray:insertionRecord];
        }
    }));
}

- (void)deleteIPRecordWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs {
    [HttpdnsUtil warnMainThreadIfNecessary];
    if (!hostRecordIDs || hostRecordIDs.count == 0) {
        return;
    }
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        for (NSNumber *hostRecordIDNumber in hostRecordIDs) {
            [db executeUpdate:ALICLOUD_HTTPDNS_SQL_DELETE_IP_RECORD withArgumentsInArray:@[ hostRecordIDNumber ]];
        }
    }));
}

- (NSArray *)insertionRecordForIP:(NSString *)IP hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL {
    return @[
             @(hostRecordId), //ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID
             IP,              //ALICLOUD_HTTPDNS_FIELD_IP
             @(TTL),          //ALICLOUD_HTTPDNS_FIELD_TTL
             ];
}

- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHostID:(NSUInteger)hostID {
    __block NSArray *IPRecords = nil;
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        IPRecords =  [self IPRecordsForHostID:hostID db:db];
    }));
    return IPRecords;
}

- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHostID:(NSUInteger)hostID db:(HttpdnsDatabase *)db {
    NSMutableArray *IPRecords = [NSMutableArray array];
    
    NSArray *args = @[ @(hostID) ];
    HttpdnsResultSet *result = [db executeQuery:ALICLOUD_HTTPDNS_SQL_SELECT_IP_RECORD withArgumentsInArray:args];
    
    while ([result next]) {
        HttpdnsIPRecord *IPRecord = [self recoedWithResult:result];
        [IPRecords addObject:IPRecord];
    }
    
    [result close];
    
    return IPRecords;
}

- (HttpdnsIPRecord *)recoedWithResult:(HttpdnsResultSet *)result {
    NSUInteger hostID = [result intForColumn:ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID];     //ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID
    NSString *IP = [result stringForColumn:ALICLOUD_HTTPDNS_FIELD_IP];                   //ALICLOUD_HTTPDNS_FIELD_IP
    int64_t TTL = [result longLongIntForColumn:ALICLOUD_HTTPDNS_FIELD_TTL];              //ALICLOUD_HTTPDNS_FIELD_TTL
    HttpdnsIPRecord *record = [HttpdnsIPRecord IPRecordWithHostRecordId:hostID IP:IP TTL:TTL];
    return record;
}

@end
