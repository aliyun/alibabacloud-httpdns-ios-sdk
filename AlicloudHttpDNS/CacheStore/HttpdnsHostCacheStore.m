//
//  HttpdnsHostCacheStore.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsHostCacheStore.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsgetNetworkInfoHelper.h"
#import "HttpdnsLog.h"
#import "HttpdnsDatabaseMigrator.h"
#import "HttpdnsHostCacheStoreSQL.h"
#import "HttpdnsConstants.h"
#import "HttpdnsIPCacheStore.h"
#import "HttpdnsUtil.h"
#import "HttpdnsIPRecord.h"
#import "HttpdnsHostCacheStore_Internal.h"

@implementation HttpdnsHostCacheStore

+ (void)initialize {
    [self configureHostCacheMaxAge];
}

+ (void)configureHostCacheMaxAge {
    ALICLOUD_HTTPDNS_HOST_CACHE_MAX_CACHE_AGE  = 60 * 60 * 24 * 7;
}

- (void)databaseQueueDidLoad {
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        [db executeUpdate:ALICLOUD_HTTPDNS_SQL_CREATE_HOST_RECORD_TABLE];
    }));
    
    [self migrateDatabaseIfNeeded:self.databaseQueue.path];
}

- (void)migrateDatabaseIfNeeded:(NSString *)databasePath {
    //后续数据库升级，兼容操作
}

- (void)insertHostRecords:(NSArray<HttpdnsHostRecord *> *)hostRecords  {
    if (!hostRecords || hostRecords.count == 0) {
        return;
    }
    [self insertHostRecords:hostRecords maxAge:ALICLOUD_HTTPDNS_HOST_CACHE_MAX_CACHE_AGE];
}

- (void)insertHostRecords:(NSArray<HttpdnsHostRecord *> *)hostRecords maxAge:(NSTimeInterval)maxAge {
    [HttpdnsUtil warnMainThreadIfNecessary];
    /** 当前网络运营商名字，或者wifi名字 */
    NSString *carrier = [HttpdnsgetNetworkInfoHelper getNetworkName];
    HttpdnsLogDebug("network named : %@", carrier);
    //当在断网状态下，carrier为nil
    if (!carrier || carrier.length == 0) {
        return;
    }
    for (HttpdnsHostRecord *hostRecord in hostRecords) {
        if (!hostRecord) continue;
        
        HttpdnsIPCacheStore *IPCacheStore = [HttpdnsIPCacheStore new];
        
        if (!hostRecord.IPs ||hostRecord.IPs.count == 0 ) {
            //删除记录，此时hostRecord.hostRecordId为nil，不能依据Id删，要先从数据库里拿id，再依据id删。
            NSArray<NSNumber *> *ids = [self hostRecordIdsForHost:hostRecord.host];
            [self deleteHostRecordAndItsIPsWithHostRecordIDs:ids];
            continue;
        }
        //Host Record表
        //先删除重复的，再插入，防止直接覆盖导致host覆盖后，IP表未更新。
        [self deleteHostRecordAndItsIPsWithHost:hostRecord.host carrier:carrier];
        NSArray *insertionRecord = [self insertionRecordForRecord:hostRecord networkName:carrier maxAge:maxAge];
        __block sqlite_int64 hostRecordId = 0;
        ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
            [db executeUpdate:ALICLOUD_HTTPDNS_SQL_INSERT_HOST_RECORD withArgumentsInArray:insertionRecord];
            //IP Record表
            hostRecordId = [db lastInsertRowId];
        }));
        HttpdnsLogDebug("hostRecordId is : %@", @(hostRecordId));
        if (hostRecordId > 0) {
            int64_t TTL = hostRecord.TTL;
            HttpdnsLogDebug("host record saved success");
            NSArray<NSString *> *IPs = hostRecord.IPs;
            [IPCacheStore insertIPs:IPs hostRecordId:(NSUInteger)hostRecordId TTL:TTL];
        }
    }
}

- (NSArray<HttpdnsHostRecord *> *)hostRecordsForCurrentCarrier {
    NSString *carrier = [HttpdnsgetNetworkInfoHelper getNetworkName];
    HttpdnsLogDebug("network named : %@", carrier);
    return [self hostRecordsForCarrier:carrier];
}

- (NSArray<HttpdnsHostRecord *> *)hostRecordsForCarrier:(NSString *)carrier {
    if (!carrier || carrier.length == 0) {
        HttpdnsLogDebug("network named is nil");
        return nil;
    }
    [HttpdnsUtil warnMainThreadIfNecessary];
    NSMutableArray *hostRecords = [NSMutableArray arrayWithCapacity:1];
    
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        NSArray *args = @[ carrier ];
        HttpdnsResultSet *result = [db executeQuery:ALICLOUD_HTTPDNS_SQL_SELECT_HOST_RECORD_WITH_CARRIER withArgumentsInArray:args];
        
        while ([result next]) {
            HttpdnsHostRecord *hostRecord = [self recordWithResult:result db:db];
            [hostRecords addObject:hostRecord];
        }
        
        [result close];
    }));
    
    
    return [hostRecords copy];
    
}

- (NSArray<NSNumber *> *)hostRecordIdsForHost:(NSString *)host {
    [HttpdnsUtil warnMainThreadIfNecessary];
    if (!host || host.length == 0) {
        return nil;
    }
    
    NSMutableArray *hostRecordIds = [NSMutableArray arrayWithCapacity:1];
    
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        NSArray *args = @[ host ];
        HttpdnsResultSet *result = [db executeQuery:ALICLOUD_HTTPDNS_SQL_SELECT_HOST_RECORD withArgumentsInArray:args];
        
        while ([result next]) {
            NSNumber *hostID = [self recordNumberIdWitResult:result];            //ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID
            [hostRecordIds addObject:hostID];
        }
        
        [result close];
    }));
    
    return [hostRecordIds copy];
}

- (HttpdnsHostRecord *)hostRecordsWithCurrentCarrierForHost:(NSString *)host {
    NSString *carrier = [HttpdnsgetNetworkInfoHelper getNetworkName];
    HttpdnsLogDebug("network named : %@", carrier);
    return [self hostRecordsForHost:host carrier:carrier];
}

- (HttpdnsHostRecord *)hostRecordsForHost:(NSString *)host carrier:(NSString *)carrier {
    [HttpdnsUtil warnMainThreadIfNecessary];
    if (!host || host.length == 0) {
        return nil;
    }
    if (!carrier || carrier.length == 0) {
        return nil;
    }
    __block HttpdnsHostRecord *hostRecord = nil;
    
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        NSArray *args = @[ host, carrier ];
        HttpdnsResultSet *result = [db executeQuery:ALICLOUD_HTTPDNS_SQL_SELECT_HOST_RECORD_WITH_HOST_AND_CARRIER withArgumentsInArray:args];
        if ([result next]) {
            HttpdnsHostRecord *hostRecordResult = [self recordWithResult:result db:db];
            hostRecord = hostRecordResult;
        }
        
        [result close];
    }));
    
    return hostRecord;
}

- (NSDate *)dateFromTimeInterval:(NSTimeInterval)timeInterval {
    return timeInterval ? [NSDate dateWithTimeIntervalSince1970:timeInterval] : nil;
}

- (NSNumber *)recordNumberIdWitResult:(HttpdnsResultSet *)result {
    NSUInteger hostID = [result intForColumn:ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID];            //ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID
    return @(hostID);
}

- (HttpdnsHostRecord *)recordWithResult:(HttpdnsResultSet *)result db:(HttpdnsDatabase *)db {
    NSUInteger hostID = [result intForColumn:ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID];            //ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID
    NSString *host = [result stringForColumn:ALICLOUD_HTTPDNS_FIELD_HOST];                      //ALICLOUD_HTTPDNS_FIELD_HOST
    NSString *carrier = [result stringForColumn:ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER];        //ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER
    
    NSTimeInterval createAtInterval = [result doubleForColumn:ALICLOUD_HTTPDNS_FIELD_CREATE_AT]; //ALICLOUD_HTTPDNS_FIELD_CREATE_AT
    NSTimeInterval expireAtInterval = [result doubleForColumn:ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT]; //ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT
    NSDate *createAt = [self dateFromTimeInterval:createAtInterval];
    NSDate *expireAt = [self dateFromTimeInterval:expireAtInterval];
    NSArray *IPs = nil;
    int64_t TTL = 0;
    if (db) {
        HttpdnsIPCacheStore *IPCacheStore = [HttpdnsIPCacheStore new];
        NSArray<HttpdnsIPRecord *> *IPRecords = [IPCacheStore IPRecordsForHostID:hostID db:db];
        @try {
            HttpdnsIPRecord *IPRecord = IPRecords[0];
            NSMutableArray *mutableIPs = [NSMutableArray arrayWithCapacity:IPRecords.count];
            for (HttpdnsIPRecord *IPRecord in IPRecords) {
                [mutableIPs addObject:IPRecord.IP];
            }
            IPs = [mutableIPs copy];
            TTL = IPRecord.TTL;
        } @catch (NSException *exception) {
            HttpdnsLogDebug("DB error, HostRecord has data with id %@, but there is not IPRecord data with same id.", @(hostID));
        }
    }
    
    HttpdnsHostRecord *record = [HttpdnsHostRecord hostRecordWithId:hostID
                                                               host:host
                                                            carrier:carrier
                                                                IPs:IPs
                                                                TTL:TTL
                                                           createAt:createAt
                                                           expireAt:expireAt];
    return record;
}

- (NSArray *)insertionRecordForRecord:(HttpdnsHostRecord *)hostRecord networkName:(NSString *)networkName maxAge:(NSTimeInterval)maxAge {
    NSTimeInterval expireAt = [[NSDate date] timeIntervalSince1970] + maxAge;
    return @[
             hostRecord.host,                               //ALICLOUD_HTTPDNS_FIELD_HOST
             networkName,                                   //ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER
             @(ALICLOUD_HTTPDNS_DISTANT_CURRENT_TIMESTAMP), //ALICLOUD_HTTPDNS_FIELD_CREATE_AT
             @(expireAt)                                    //ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT
             ];
}

- (void)deleteHostRecordAndItsIPsWithHost:(NSString *)host carrier:(NSString *)carrier {
    if (!host || host.length == 0) {
        return;
    }
    if (!carrier || carrier.length == 0) {
        return;
    }
    HttpdnsHostRecord *hostRecord = [self hostRecordsForHost:host carrier:carrier];
    if (!hostRecord) {
        return;
    }
    NSArray<NSNumber *> *hostRecordIDs = @[@(hostRecord.hostRecordId)];
    [self deleteHostRecordAndItsIPsWithHostRecordIDs:hostRecordIDs];
}

- (void)deleteHostRecordAndItsIPsWithHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs {
    if (!hostRecordIDs || hostRecordIDs.count == 0) {
        return;
    }
    [self deleteHostRecordWithHostIds:hostRecordIDs];
    [self deleteIPCacheForHostRecordIDs:hostRecordIDs];
}

- (void)cleanAllExpiredHostRecordsSync {
    [HttpdnsUtil warnMainThreadIfNecessary];
    NSArray<NSNumber *> *hostIds = [self allExpiredHostRecordNumbers];
    [self deleteHostRecordAndItsIPsWithHostRecordIDs:hostIds];
}

#pragma mark -
#pragma mark - Private Methods

- (NSArray<NSNumber *> *)allExpiredHostRecordNumbers {
    [HttpdnsUtil warnMainThreadIfNecessary];
    NSMutableArray *hostRecordNumbers = [NSMutableArray array];
    
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        NSArray *args = @[[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]];
        HttpdnsResultSet *result = [db executeQuery:ALICLOUD_HTTPDNS_SQL_SELECT_EXPIRED_HOST_RECORD withArgumentsInArray:args];
        
        while ([result next]) {
            NSNumber *hostID = [self recordNumberIdWitResult:result];
            [hostRecordNumbers addObject:hostID];
        }
        
        [result close];
    }));
    
    return [hostRecordNumbers copy];
}

- (NSArray<NSNumber *> *)hostIdsFromHostRecords:(NSArray<HttpdnsHostRecord *> *)hostRecords {
    if (!hostRecords || hostRecords.count == 0) {
        return nil;
    }
    NSMutableArray *hostIds = [NSMutableArray arrayWithCapacity:hostRecords.count];
    for (HttpdnsHostRecord *hostRecord in hostRecords) {
        [hostIds addObject:@(hostRecord.hostRecordId)];
    }
    return [hostIds copy];
}

- (void)deleteHostRecordWithHostIds:(NSArray<NSNumber *> *)hostIds {
    [HttpdnsUtil warnMainThreadIfNecessary];
    if (!hostIds || hostIds.count == 0) {
        return;
    }
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        for (NSNumber *hostIdNumber in hostIds) {
            [db executeUpdate:ALICLOUD_HTTPDNS_SQL_DELETE_HOST_RECORD_WITH_HOST_ID withArgumentsInArray:@[hostIdNumber]];
        }
    }));
}

- (void)deleteIPCacheForHostRecordIDs:(NSArray<NSNumber *> *)hostRecordIDs {
    if (!hostRecordIDs || hostRecordIDs.count == 0) {
        return;
    }
    [HttpdnsUtil warnMainThreadIfNecessary];
    HttpdnsIPCacheStore *IPCacheStore = [HttpdnsIPCacheStore new];
    [IPCacheStore deleteIPRecordWithHostRecordIDs:hostRecordIDs];
}

@end

@implementation HttpdnsHostCacheStoreTestHelper

+ (void)shortCacheExpireTime {
    ALICLOUD_HTTPDNS_HOST_CACHE_MAX_CACHE_AGE  = 5;//60 * 60 * 24 * 7
}

@end
