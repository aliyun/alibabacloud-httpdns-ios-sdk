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
#import "HttpdnsLog.h"
#import "LCDatabaseMigrator.h"
#import "HttpdnsHostCacheStoreSQL.h"
#import "HttpdnsConstants.h"

@implementation HttpdnsHostCacheStore

- (void)databaseQueueDidLoad {
    LCIM_OPEN_DATABASE(db, ({
        [db executeUpdate:ALICLOUD_HTTPDNS_SQL_CREATE_CONVERSATION_TABLE];
    }));
    
    [self migrateDatabaseIfNeeded:self.databaseQueue.path];
}

- (void)migrateDatabaseIfNeeded:(NSString *)databasePath {
//    LCDatabaseMigrator *migrator = [[LCDatabaseMigrator alloc] initWithDatabasePath:databasePath];
//    
//    [migrator executeMigrations:@[
//                                  /* Version 1: Add muted column. */
//                                  [LCDatabaseMigration migrationWithBlock:^(LCDatabase *db) {
//        [db executeUpdate:@"ALTER TABLE conversation ADD COLUMN muted INTEGER"];
//    }]
//                                  ]];
}

- (void)insertHostRecords:(NSArray<HttpdnsHostRecord *> *)HostRecords {
    /** 当前网络运营商名字，或者wifi名字 */
    NSString *networkName = [HttpdnsgetNetworkInfoHelper getNetworkName];
    HttpdnsLogDebug("network named : %@", networkName);
    if (!networkName || networkName.length == 0) {
        return;
    }
    
    LCIM_OPEN_DATABASE(db, ({
        for (HttpdnsHostRecord *hostRecord in HostRecords) {
            if (!hostRecord) continue;
            if (!hostRecord.IPs ||hostRecord.IPs.count == 0 ) {
                //TODO:删除记录
                continue;
            }
            //Host Record表
            NSArray *insertionRecord = [self insertionRecordForHostRecord:hostRecord networkName:networkName];
            [db executeUpdate:ALICLOUD_HTTPDNS_SQL_INSERT_CONVERSATION withArgumentsInArray:insertionRecord];
            
            //IP Record表
            sqlite_int64 hostRecordId = [db lastInsertRowId];
            HttpdnsLogDebug("hostRecordId is : %@", @(hostRecordId));
            if (hostRecordId > 0) {
                HttpdnsLogDebug("host record saved success");
            }
        }
    }));
}

- (NSArray *)insertionRecordForHostRecord:(HttpdnsHostRecord *)hostRecord networkName:(NSString *)networkName {
    return @[
             hostRecord.host,                                                         //ALICLOUD_HTTPDNS_FIELD_HOST
             networkName,                                                             //ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER
             [NSNumber numberWithInteger:ALICLOUD_HTTPDNS_DISTANT_CURRENT_TIMESTAMP], //ALICLOUD_HTTPDNS_FIELD_TIMESTAMP
             hostRecord.IPs                                                           //ALICLOUD_HTTPDNS_FIELD_IPS
             ];
}

- (void)deleteHostRecord:(HttpdnsHostRecord *)HostRecord {
    
}

- (void)deleteHostRecordForHost:(NSString *)host {
    
}

- (NSArray<HttpdnsHostRecord *> *)hostRecordsForHosts:(NSArray<NSString *> *)hosts {
    return nil;
}

@end
