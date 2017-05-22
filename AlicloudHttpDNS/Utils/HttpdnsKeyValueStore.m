//
//  HttpdnsKeyValueStore.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsKeyValueStore.h"
#import "HttpdnsKeyValueSQL.h"
#import "HttpdnsDatabase.h"
#import "HttpdnsDatabaseQueue.h"
#import "HttpdnsPersistenceUtils.h"

#import <libkern/OSAtomic.h>

#ifdef DEBUG
static BOOL shouldLogError = YES;
#else
static BOOL shouldLogError = NO;
#endif

#define ALICLOUD_HTTPDNS_OPEN_DATABASE(db, routine) do {        \
    [self.dbQueue inDatabase:^(HttpdnsDatabase *db) {  \
        db.logsErrors = shouldLogError;           \
        routine;                                  \
    }];                                           \
} while (0)

static OSSpinLock dbQueueLock = OS_SPINLOCK_INIT;

@interface HttpdnsKeyValueStore () {
    NSString *_dbPath;
    NSString *_tableName;
    HttpdnsDatabaseQueue *_dbQueue;
}

- (NSString *)dbPath;
- (NSString *)tableName;
- (HttpdnsDatabaseQueue *)dbQueue;

@end

@implementation HttpdnsKeyValueStore

+ (instancetype)sharedInstance {
    static HttpdnsKeyValueStore *instance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });

    return instance;
}

- (instancetype)initWithDatabasePath:(NSString *)databasePath {
    self = [super init];

    if (self) {
        _dbPath = [databasePath copy];
    }

    return self;
}

- (instancetype)initWithDatabasePath:(NSString *)databasePath tableName:(NSString *)tableName {
    self = [self initWithDatabasePath:databasePath];

    if (self) {
        _tableName = [tableName copy];
    }

    return self;
}

- (NSString *)formatSQL:(NSString *)SQL withTableName:(NSString *)tableName {
    return [NSString stringWithFormat:SQL, tableName];
}

- (NSData *)dataForKey:(NSString *)key {
    __block NSData *data = nil;

    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        NSArray *args = @[key];
        NSString *SQL = [self formatSQL:ALICLOUD_HTTPDNS_SQL_SELECT_KEY_VALUE_FMT withTableName:[self tableName]];
        HttpdnsResultSet *result = [db executeQuery:SQL withArgumentsInArray:args];

        if ([result next]) {
            data = [result dataForColumn:ALICLOUD_HTTPDNS_FIELD_VALUE];
        }

        [result close];
    }));

    return data;
}

- (void)setData:(NSData *)data forKey:(NSString *)key {
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        NSArray *args = @[key, data];
        NSString *SQL = [self formatSQL:ALICLOUD_HTTPDNS_SQL_UPDATE_KEY_VALUE_FMT withTableName:[self tableName]];
        [db executeUpdate:SQL withArgumentsInArray:args];
    }));
}

- (void)deleteKey:(NSString *)key {
    ALICLOUD_HTTPDNS_OPEN_DATABASE(db, ({
        NSArray *args = @[key];
        NSString *SQL = [self formatSQL:ALICLOUD_HTTPDNS_SQL_DELETE_KEY_VALUE_FMT withTableName:[self tableName]];
        [db executeUpdate:SQL withArgumentsInArray:args];
    }));
}

- (void)createSchemeForDatabaseQueue:(HttpdnsDatabaseQueue *)dbQueue {
    [dbQueue inDatabase:^(HttpdnsDatabase *db) {
        db.logsErrors = shouldLogError;

        NSString *SQL = [self formatSQL:ALICLOUD_HTTPDNS_SQL_CREATE_KEY_VALUE_TABLE_FMT withTableName:[self tableName]];
        [db executeUpdate:SQL];
    }];
}

- (NSString *)dbPath {
    return _dbPath ?: [HttpdnsPersistenceUtils keyValueDatabasePath];
}

- (NSString *)tableName {
    return _tableName ?: ALICLOUD_HTTPDNS_TABLE_KEY_VALUE;
}

- (HttpdnsDatabaseQueue *)dbQueue {
    OSSpinLockLock(&dbQueueLock);

    if (!_dbQueue) {
        _dbQueue = [HttpdnsDatabaseQueue databaseQueueWithPath:[self dbPath]];

        [self createSchemeForDatabaseQueue:_dbQueue];
    }

    OSSpinLockUnlock(&dbQueueLock);

    return _dbQueue;
}

@end
