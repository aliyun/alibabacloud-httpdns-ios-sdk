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
#import "HttpdnsIP6CacheStoreSQL.h"
#import "HttpdnsUtil.h"

@implementation HttpdnsIPCacheStore

+ (instancetype)sharedInstance {
    static id singletonInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!singletonInstance) {
            singletonInstance = [[super allocWithZone:NULL] init];
        }
    });
    return singletonInstance;
}

- (void)databaseQueueDidLoad {
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        [db executeUpdate:ALICLOUD_HTTPDNS_SQL_CREATE_IP_RECORD_TABLE];
        [db executeUpdate:ALICLOUD_HTTPDNS_SQL_CREATE_IP6_RECORD_TABLE];
    }));
    
    [self migrateDatabaseIfNeeded:self.databaseQueue.path];
}

- (void)migrateDatabaseIfNeeded:(NSString *)databasePath {
    //后续数据库升级，兼容操作
    
    //ip ip6两张表增加region列
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        HttpdnsResultSet *result = [db executeQuery:ALICLOUD_HTTPDNS_SQL_FIND_REGION withArgumentsInArray:@[]];
        if (!result.next) {
            [db executeUpdate:ALICLOUD_HTTPDNS_SQL_ADD_IP_COLUMN_REGION];
        }
        [result close];
        
        HttpdnsResultSet *result_ip6 = [db executeQuery:ALICLOUD_HTTPDNS_SQL_FIND_IP6_REGION withArgumentsInArray:@[]];
        if (!result_ip6.next) {
            [db executeUpdate:ALICLOUD_HTTPDNS_SQL_ADD_IP_COLUMN_IP6_REGION];
        }
        [result_ip6 close];
    }));
}

- (void)insertIPs:(NSArray<NSString *> *)IPs hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL ipRegion:(NSString *)ipRegion{
    [self innerInsertIPs:IPs hostRecordId:hostRecordId TTL:TTL isIPv6:NO ipRegion:ipRegion ip6Region:@""];
}

- (void)insertIP6s:(NSArray<NSString *> *)IPs hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL ip6Region:(NSString *)ip6Region{
    [self innerInsertIPs:IPs hostRecordId:hostRecordId TTL:TTL isIPv6:YES ipRegion:@"" ip6Region:ip6Region];
}

- (void)innerInsertIPs:(NSArray<NSString *> *)IPs hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL isIPv6:(BOOL)isIPv6 ipRegion:(NSString *)ipRegion ip6Region:(NSString *)ip6Region{
    [HttpdnsUtil warnMainThreadIfNecessary];
    NSString *sqlStr = (isIPv6) ? ALICLOUD_HTTPDNS_SQL_INSERT_IP6_RECORD : ALICLOUD_HTTPDNS_SQL_INSERT_IP_RECORD;
    if (!IPs || IPs.count == 0) {
        return;
    }
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        for (NSString *IP in IPs) {
            NSArray *insertionRecord = [self insertionRecordForIP:IP hostRecordId:hostRecordId TTL:TTL ipRegion:isIPv6?ip6Region:ipRegion];
            [db executeUpdate:sqlStr withArgumentsInArray:insertionRecord];
        }
    }));
}

- (void)deleteIPRecordWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs {
    [self innerDeleteIPRecordWithHostRecordIDs:hostRecordIDs isIPv6:NO];
}

- (void)deleteIP6RecordWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs {
    [self innerDeleteIPRecordWithHostRecordIDs:hostRecordIDs isIPv6:YES];
}

- (void)innerDeleteIPRecordWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs isIPv6:(BOOL)isIPv6 {
    [HttpdnsUtil warnMainThreadIfNecessary];
    NSString *sqlStr = (isIPv6) ? ALICLOUD_HTTPDNS_SQL_DELETE_IP6_RECORD : ALICLOUD_HTTPDNS_SQL_DELETE_IP_RECORD;
    if (!hostRecordIDs || hostRecordIDs.count == 0) {
        return;
    }
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        for (NSNumber *hostRecordIDNumber in hostRecordIDs) {
            [db executeUpdate:sqlStr withArgumentsInArray:@[ hostRecordIDNumber ]];
        }
    }));
}

- (NSArray *)insertionRecordForIP:(NSString *)IP hostRecordId:(NSUInteger)hostRecordId TTL:(int64_t)TTL ipRegion:(NSString *)ipRegion{
    return @[
             @(hostRecordId), //ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID
             IP,              //ALICLOUD_HTTPDNS_FIELD_IP
             @(TTL),          //ALICLOUD_HTTPDNS_FIELD_TTL
             ipRegion?:@"",   //ALICLOUD_HTTPDNS_FIELD_REGION
             ];
}

- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHostID:(NSUInteger)hostID {
    return [self innerIPRecordsForHostID:hostID isIPv6:NO];
}

- (NSArray<HttpdnsIPRecord *> *)IP6RecordsForHostID:(NSUInteger)hostID {
    return [self innerIPRecordsForHostID:hostID isIPv6:YES];
}

- (NSArray<HttpdnsIPRecord *> *)innerIPRecordsForHostID:(NSUInteger)hostID isIPv6:(BOOL)isIPv6 {
    __block NSArray *IPRecords = nil;
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        IPRecords =  [self innerIPRecordsForHostID:hostID db:db isIPv6:isIPv6];
    }));
    return IPRecords;
}

- (NSArray<HttpdnsIPRecord *> *)IPRecordsForHostID:(NSUInteger)hostID db:(HttpdnsDatabase *)db {
    return [self innerIPRecordsForHostID:hostID db:db isIPv6:NO];
}

- (NSArray<HttpdnsIPRecord *> *)IP6RecordsForHostID:(NSUInteger)hostID db:(HttpdnsDatabase *)db {
    return [self innerIPRecordsForHostID:hostID db:db isIPv6:YES];
}

- (NSArray<HttpdnsIPRecord *> *)innerIPRecordsForHostID:(NSUInteger)hostID db:(HttpdnsDatabase *)db isIPv6:(BOOL)isIPv6 {
    NSMutableArray *IPRecords = [NSMutableArray array];
    NSString *sqlStr = (isIPv6) ? ALICLOUD_HTTPDNS_SQL_SELECT_IP6_RECORD : ALICLOUD_HTTPDNS_SQL_SELECT_IP_RECORD;
    NSArray *args = @[ @(hostID) ];
    HttpdnsResultSet *result = [db executeQuery:sqlStr withArgumentsInArray:args];
    
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
    NSString *region = [result stringForColumn:ALICLOUD_HTTPDNS_FIELD_REGION];           //ALICLOUD_HTTPDNS_FIELD_REGION
    HttpdnsIPRecord *record = [HttpdnsIPRecord IPRecordWithHostRecordId:hostID IP:IP TTL:TTL region:region];
    return record;
}

- (void)cleanIPRecord {
    [HttpdnsUtil warnMainThreadIfNecessary];
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        [db executeUpdate:ALICLOUD_HTTPDNS_SQL_CLEAN_IP_RECORD_TABLE];
    }));
}

- (void)cleanIP6Record {
    [HttpdnsUtil warnMainThreadIfNecessary];
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        [db executeUpdate:ALICLOUD_HTTPDNS_SQL_CLEAN_IP6_RECORD_TABLE];
    }));
}

@end
