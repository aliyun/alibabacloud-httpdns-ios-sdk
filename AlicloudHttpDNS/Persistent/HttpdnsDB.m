//
//  HttpdnsDB.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/15.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsDB.h"
#import <sqlite3.h>

// 表名
static NSString *const kTableName = @"httpdns_cache_table";

// 列名
static NSString *const kColumnId = @"id";
static NSString *const kColumnCacheKey = @"cache_key";
static NSString *const kColumnHostName = @"host_name";
static NSString *const kColumnCreateAt = @"create_at";
static NSString *const kColumnModifyAt = @"modify_at";
static NSString *const kColumnClientIp = @"client_ip";
static NSString *const kColumnV4Ips = @"v4_ips";
static NSString *const kColumnV4Ttl = @"v4_ttl";
static NSString *const kColumnV4LookupTime = @"v4_lookup_time";
static NSString *const kColumnV6Ips = @"v6_ips";
static NSString *const kColumnV6Ttl = @"v6_ttl";
static NSString *const kColumnV6LookupTime = @"v6_lookup_time";
static NSString *const kColumnExtra = @"extra";

@interface HttpdnsDB ()

@property (nonatomic, assign) sqlite3 *db;
@property (nonatomic, copy) NSString *dbPath;
@property (nonatomic, strong) dispatch_queue_t dbQueue;

@end

@implementation HttpdnsDB

- (instancetype)initWithAccountId:(NSInteger)accountId {
    self = [super init];
    if (self) {
        // 创建数据库目录
        NSString *dbDir = [NSHomeDirectory() stringByAppendingPathComponent:@"httpdns"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:dbDir]) {
            NSError *error = nil;
            [fileManager createDirectoryAtPath:dbDir withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                NSLog(@"Failed to create database directory: %@", error);
                return nil;
            }
        }

        // 设置数据库路径
        _dbPath = [dbDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld.db", (long)accountId]];

        // 创建专用队列确保线程安全
        _dbQueue = dispatch_queue_create("com.aliyun.httpdns.db", DISPATCH_QUEUE_SERIAL);

        // 打开数据库
        __block BOOL success = NO;
        dispatch_sync(_dbQueue, ^{
            success = [self openDB];
        });

        if (!success) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
    }
}

#pragma mark - Public Methods

- (BOOL)createOrUpdate:(HttpdnsHostRecord *)record {
    if (!record || !record.cacheKey) {
        return NO;
    }

    __block BOOL result = NO;
    dispatch_sync(_dbQueue, ^{
        // 检查记录是否存在，以便正确处理createAt
        HttpdnsHostRecord *existingRecord = [self selectByCacheKeyInternal:record.cacheKey];

        // 准备要保存的记录
        NSDate *now = [NSDate date];
        HttpdnsHostRecord *recordToSave;

        if (existingRecord) {
            // 更新记录，保留原始的createAt，更新modifyAt为当前时间
            recordToSave = [[HttpdnsHostRecord alloc] initWithId:record.id
                                                        cacheKey:record.cacheKey
                                                        hostName:record.hostName
                                                        createAt:existingRecord.createAt // 保留原始createAt
                                                        modifyAt:now // 更新modifyAt
                                                        clientIp:record.clientIp
                                                           v4ips:record.v4ips
                                                           v4ttl:record.v4ttl
                                                    v4LookupTime:record.v4LookupTime
                                                           v6ips:record.v6ips
                                                           v6ttl:record.v6ttl
                                                    v6LookupTime:record.v6LookupTime
                                                           extra:record.extra];
        } else {
            // 新记录，设置createAt和modifyAt为当前时间
            recordToSave = [[HttpdnsHostRecord alloc] initWithId:record.id
                                                        cacheKey:record.cacheKey
                                                        hostName:record.hostName
                                                        createAt:now // 新记录的createAt
                                                        modifyAt:now // 新记录的modifyAt
                                                        clientIp:record.clientIp
                                                           v4ips:record.v4ips
                                                           v4ttl:record.v4ttl
                                                    v4LookupTime:record.v4LookupTime
                                                           v6ips:record.v6ips
                                                           v6ttl:record.v6ttl
                                                    v6LookupTime:record.v6LookupTime
                                                           extra:record.extra];
        }

        // 使用INSERT OR REPLACE语法保存记录
        result = [self saveRecord:recordToSave];
    });

    return result;
}

- (nullable HttpdnsHostRecord *)selectByCacheKey:(NSString *)cacheKey {
    if (!cacheKey) {
        return nil;
    }

    __block HttpdnsHostRecord *record = nil;
    dispatch_sync(_dbQueue, ^{
        record = [self selectByCacheKeyInternal:cacheKey];
    });

    return record;
}

- (nullable HttpdnsHostRecord *)selectByHostname:(NSString *)hostname {
    if (!hostname) {
        return nil;
    }

    __block HttpdnsHostRecord *record = nil;
    dispatch_sync(_dbQueue, ^{
        // Since hostname is no longer unique, we'll return the first matching record
        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ = ? LIMIT 1", kTableName, kColumnHostName];
        sqlite3_stmt *stmt;

        if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [hostname UTF8String], -1, SQLITE_TRANSIENT);

            if (sqlite3_step(stmt) == SQLITE_ROW) {
                record = [self recordFromStatement:stmt];
            }

            sqlite3_finalize(stmt);
        }
    });

    return record;
}

- (NSArray<HttpdnsHostRecord *> *)selectAllByHostname:(NSString *)hostname {
    if (!hostname) {
        return @[];
    }

    __block NSMutableArray<HttpdnsHostRecord *> *records = [NSMutableArray array];
    dispatch_sync(_dbQueue, ^{
        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ = ?", kTableName, kColumnHostName];
        sqlite3_stmt *stmt;

        if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [hostname UTF8String], -1, SQLITE_TRANSIENT);

            while (sqlite3_step(stmt) == SQLITE_ROW) {
                HttpdnsHostRecord *record = [self recordFromStatement:stmt];
                [records addObject:record];
            }

            sqlite3_finalize(stmt);
        }
    });

    return [records copy];
}

- (BOOL)deleteByCacheKey:(NSString *)cacheKey {
    if (!cacheKey) {
        return NO;
    }

    __block BOOL result = NO;
    dispatch_sync(_dbQueue, ^{
        NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = ?", kTableName, kColumnCacheKey];
        sqlite3_stmt *stmt;

        if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [cacheKey UTF8String], -1, SQLITE_TRANSIENT);

            result = (sqlite3_step(stmt) == SQLITE_DONE);
            sqlite3_finalize(stmt);
        }
    });

    return result;
}

- (NSInteger)deleteByHostNameArr:(NSArray<NSString *> *)hostNameArr {
    if (!hostNameArr || hostNameArr.count == 0) {
        return 0;
    }

    // 过滤掉空值
    NSMutableArray *validHostNames = [NSMutableArray array];
    for (NSString *hostname in hostNameArr) {
        if (hostname && hostname.length > 0) {
            [validHostNames addObject:hostname];
        }
    }

    if (validHostNames.count == 0) {
        return 0;
    }

    __block NSInteger deletedCount = 0;

    dispatch_sync(_dbQueue, ^{
        // 构建IN子句的占位符
        NSMutableString *placeholders = [NSMutableString string];
        for (NSUInteger i = 0; i < validHostNames.count; i++) {
            [placeholders appendString:@"?"];
            if (i < validHostNames.count - 1) {
                [placeholders appendString:@","];
            }
        }

        // 构建SQL语句
        NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ IN (%@)",
                         kTableName, kColumnHostName, placeholders];

        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            // 绑定所有参数
            for (NSUInteger i = 0; i < validHostNames.count; i++) {
                sqlite3_bind_text(stmt, (int)(i + 1), [validHostNames[i] UTF8String], -1, SQLITE_TRANSIENT);
            }

            // 执行删除
            if (sqlite3_step(stmt) == SQLITE_DONE) {
                deletedCount = sqlite3_changes(_db);
            } else {
                NSLog(@"Failed to delete records: %s", sqlite3_errmsg(_db));
            }

            sqlite3_finalize(stmt);
        } else {
            NSLog(@"Failed to prepare delete statement: %s", sqlite3_errmsg(_db));
        }
    });

    return deletedCount;
}

- (BOOL)deleteAll {
    __block BOOL result = NO;
    dispatch_sync(_dbQueue, ^{
        NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@", kTableName];
        char *errMsg;

        result = (sqlite3_exec(_db, [sql UTF8String], NULL, NULL, &errMsg) == SQLITE_OK);

        if (errMsg) {
            NSLog(@"Failed to delete all records: %s", errMsg);
            sqlite3_free(errMsg);
        }
    });

    return result;
}

- (NSArray<HttpdnsHostRecord *> *)getAllRecords {
    __block NSMutableArray<HttpdnsHostRecord *> *records = [NSMutableArray array];

    dispatch_sync(_dbQueue, ^{
        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@", kTableName];
        sqlite3_stmt *stmt;

        if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                HttpdnsHostRecord *record = [self recordFromStatement:stmt];
                if (record) {
                    [records addObject:record];
                }
            }

            sqlite3_finalize(stmt);
        } else {
            NSLog(@"Failed to prepare getAllRecords statement: %s", sqlite3_errmsg(_db));
        }
    });

    return [records copy];
}

- (NSInteger)cleanRecordAlreadExpiredAt:(NSTimeInterval)specifiedTime {
    __block NSInteger cleanedCount = 0;

    // 获取所有记录
    NSArray<HttpdnsHostRecord *> *allRecords = [self getAllRecords];

    dispatch_sync(_dbQueue, ^{
        for (HttpdnsHostRecord *record in allRecords) {
            BOOL v4Expired = NO;
            BOOL v6Expired = NO;

            // 检查IPv4记录是否过期
            if (record.v4LookupTime + record.v4ttl <= specifiedTime) {
                v4Expired = YES;
            }

            // 检查IPv6记录是否过期
            if (record.v6LookupTime + record.v6ttl <= specifiedTime) {
                v6Expired = YES;
            }

            // 如果两种IP类型都过期，删除整条记录
            if (v4Expired && v6Expired) {
                NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = ?", kTableName, kColumnCacheKey];
                sqlite3_stmt *stmt;

                if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
                    sqlite3_bind_text(stmt, 1, [record.cacheKey UTF8String], -1, SQLITE_TRANSIENT);

                    if (sqlite3_step(stmt) == SQLITE_DONE) {
                        cleanedCount++;
                    }

                    sqlite3_finalize(stmt);
                }
            }
            // 如果只有一种IP类型过期，更新记录
            else if (v4Expired || v6Expired) {
                NSMutableArray<NSString *> *v4ips = [NSMutableArray arrayWithArray:record.v4ips];
                NSMutableArray<NSString *> *v6ips = [NSMutableArray arrayWithArray:record.v6ips];

                // 如果IPv4过期，清空IPv4记录
                if (v4Expired) {
                    [v4ips removeAllObjects];
                }

                // 如果IPv6过期，清空IPv6记录
                if (v6Expired) {
                    [v6ips removeAllObjects];
                }

                // 更新记录
                NSString *sql = [NSString stringWithFormat:
                                @"UPDATE %@ SET %@ = ?, %@ = ? WHERE %@ = ?",
                                kTableName,
                                kColumnV4Ips,
                                kColumnV6Ips,
                                kColumnCacheKey];
                sqlite3_stmt *stmt;

                if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
                    // 绑定v4ips
                    if (v4ips.count > 0) {
                        NSString *v4ipsStr = [v4ips componentsJoinedByString:@","];
                        sqlite3_bind_text(stmt, 1, [v4ipsStr UTF8String], -1, SQLITE_TRANSIENT);
                    } else {
                        sqlite3_bind_null(stmt, 1);
                    }

                    // 绑定v6ips
                    if (v6ips.count > 0) {
                        NSString *v6ipsStr = [v6ips componentsJoinedByString:@","];
                        sqlite3_bind_text(stmt, 2, [v6ipsStr UTF8String], -1, SQLITE_TRANSIENT);
                    } else {
                        sqlite3_bind_null(stmt, 2);
                    }

                    // 绑定cacheKey
                    sqlite3_bind_text(stmt, 3, [record.cacheKey UTF8String], -1, SQLITE_TRANSIENT);

                    if (sqlite3_step(stmt) == SQLITE_DONE) {
                        cleanedCount++;
                    }

                    sqlite3_finalize(stmt);
                }
            }
        }
    });

    return cleanedCount;
}

#pragma mark - Private Methods

- (BOOL)openDB {
    if (sqlite3_open([_dbPath UTF8String], &_db) != SQLITE_OK) {
        NSLog(@"Failed to open database: %s", sqlite3_errmsg(_db));
        return NO;
    }

    // 创建表
    return [self createTableIfNeeded];
}

- (BOOL)createTableIfNeeded {
    NSString *sql = [NSString stringWithFormat:
                     @"CREATE TABLE IF NOT EXISTS %@ ("
                     @"%@ INTEGER PRIMARY KEY AUTOINCREMENT, "
                     @"%@ TEXT UNIQUE NOT NULL, "
                     @"%@ TEXT NOT NULL, "
                     @"%@ REAL, "
                     @"%@ REAL, "
                     @"%@ TEXT, "
                     @"%@ TEXT, "
                     @"%@ INTEGER, "
                     @"%@ INTEGER, "
                     @"%@ TEXT, "
                     @"%@ INTEGER, "
                     @"%@ INTEGER, "
                     @"%@ TEXT"
                     @")",
                     kTableName,
                     kColumnId,
                     kColumnCacheKey,
                     kColumnHostName,
                     kColumnCreateAt,
                     kColumnModifyAt,
                     kColumnClientIp,
                     kColumnV4Ips,
                     kColumnV4Ttl,
                     kColumnV4LookupTime,
                     kColumnV6Ips,
                     kColumnV6Ttl,
                     kColumnV6LookupTime,
                     kColumnExtra];

    char *errMsg;
    if (sqlite3_exec(_db, [sql UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
        NSLog(@"Failed to create table: %s", errMsg);
        sqlite3_free(errMsg);
        return NO;
    }

    return YES;
}

- (BOOL)saveRecord:(HttpdnsHostRecord *)record {
    // 使用INSERT OR REPLACE语法，如果记录存在则更新，不存在则插入
    NSString *sql = [NSString stringWithFormat:
                     @"INSERT OR REPLACE INTO %@ ("
                     @"%@, %@, %@, %@, %@, %@, %@, %@, %@, %@, %@, %@) "
                     @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                     kTableName,
                     kColumnCacheKey,
                     kColumnHostName,
                     kColumnCreateAt,
                     kColumnModifyAt,
                     kColumnClientIp,
                     kColumnV4Ips,
                     kColumnV4Ttl,
                     kColumnV4LookupTime,
                     kColumnV6Ips,
                     kColumnV6Ttl,
                     kColumnV6LookupTime,
                     kColumnExtra];

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        NSLog(@"Failed to prepare save statement: %s", sqlite3_errmsg(_db));
        return NO;
    }

    // 绑定参数
    int index = 1;

    // 绑定cacheKey (唯一键)
    sqlite3_bind_text(stmt, index++, [record.cacheKey UTF8String], -1, SQLITE_TRANSIENT);

    // 绑定hostName
    sqlite3_bind_text(stmt, index++, [record.hostName UTF8String], -1, SQLITE_TRANSIENT);

    // 绑定createAt
    if (record.createAt) {
        sqlite3_bind_double(stmt, index++, [record.createAt timeIntervalSince1970]);
    } else {
        sqlite3_bind_null(stmt, index++);
    }

    // 绑定modifyAt
    if (record.modifyAt) {
        sqlite3_bind_double(stmt, index++, [record.modifyAt timeIntervalSince1970]);
    } else {
        sqlite3_bind_null(stmt, index++);
    }

    // 绑定clientIp
    if (record.clientIp) {
        sqlite3_bind_text(stmt, index++, [record.clientIp UTF8String], -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, index++);
    }

    // 绑定v4ips
    if (record.v4ips.count > 0) {
        NSString *v4ipsStr = [record.v4ips componentsJoinedByString:@","];
        sqlite3_bind_text(stmt, index++, [v4ipsStr UTF8String], -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, index++);
    }

    // 绑定v4ttl
    sqlite3_bind_int64(stmt, index++, record.v4ttl);

    // 绑定v4LookupTime
    sqlite3_bind_int64(stmt, index++, record.v4LookupTime);

    // 绑定v6ips
    if (record.v6ips.count > 0) {
        NSString *v6ipsStr = [record.v6ips componentsJoinedByString:@","];
        sqlite3_bind_text(stmt, index++, [v6ipsStr UTF8String], -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, index++);
    }

    // 绑定v6ttl
    sqlite3_bind_int64(stmt, index++, record.v6ttl);

    // 绑定v6LookupTime
    sqlite3_bind_int64(stmt, index++, record.v6LookupTime);

    // 绑定extra
    if (record.extra.count > 0) {
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record.extra options:0 error:&error];
        if (!error && jsonData) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            sqlite3_bind_text(stmt, index++, [jsonString UTF8String], -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, index++);
        }
    } else {
        sqlite3_bind_null(stmt, index++);
    }

    BOOL result = (sqlite3_step(stmt) == SQLITE_DONE);
    sqlite3_finalize(stmt);

    return result;
}

- (HttpdnsHostRecord *)selectByCacheKeyInternal:(NSString *)cacheKey {
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ = ?", kTableName, kColumnCacheKey];
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        NSLog(@"Failed to prepare query statement: %s", sqlite3_errmsg(_db));
        return nil;
    }

    sqlite3_bind_text(stmt, 1, [cacheKey UTF8String], -1, SQLITE_TRANSIENT);

    HttpdnsHostRecord *record = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        record = [self recordFromStatement:stmt];
    }

    sqlite3_finalize(stmt);
    return record;
}

- (HttpdnsHostRecord *)recordFromStatement:(sqlite3_stmt *)stmt {
    // 获取id
    NSUInteger recordId = (NSUInteger)sqlite3_column_int64(stmt, 0);

    // 获取cacheKey
    const char *cacheKeyChars = (const char *)sqlite3_column_text(stmt, 1);
    NSString *cacheKey = cacheKeyChars ? [NSString stringWithUTF8String:cacheKeyChars] : nil;

    // 获取hostName
    const char *hostNameChars = (const char *)sqlite3_column_text(stmt, 2);
    NSString *hostName = hostNameChars ? [NSString stringWithUTF8String:hostNameChars] : nil;

    // 获取createAt
    NSDate *createAt = nil;
    if (sqlite3_column_type(stmt, 3) != SQLITE_NULL) {
        double createAtTimestamp = sqlite3_column_double(stmt, 3);
        createAt = [NSDate dateWithTimeIntervalSince1970:createAtTimestamp];
    }

    // 获取modifyAt
    NSDate *modifyAt = nil;
    if (sqlite3_column_type(stmt, 4) != SQLITE_NULL) {
        double modifyAtTimestamp = sqlite3_column_double(stmt, 4);
        modifyAt = [NSDate dateWithTimeIntervalSince1970:modifyAtTimestamp];
    }

    // 获取clientIp
    const char *clientIpChars = (const char *)sqlite3_column_text(stmt, 5);
    NSString *clientIp = clientIpChars ? [NSString stringWithUTF8String:clientIpChars] : nil;

    // 获取v4ips
    NSArray<NSString *> *v4ips = nil;
    const char *v4ipsChars = (const char *)sqlite3_column_text(stmt, 6);
    if (v4ipsChars) {
        NSString *v4ipsStr = [NSString stringWithUTF8String:v4ipsChars];
        v4ips = [v4ipsStr componentsSeparatedByString:@","];
    } else {
        v4ips = @[];
    }

    // 获取v4ttl
    int64_t v4ttl = sqlite3_column_int64(stmt, 7);

    // 获取v4LookupTime
    int64_t v4LookupTime = sqlite3_column_int64(stmt, 8);

    // 获取v6ips
    NSArray<NSString *> *v6ips = nil;
    const char *v6ipsChars = (const char *)sqlite3_column_text(stmt, 9);
    if (v6ipsChars) {
        NSString *v6ipsStr = [NSString stringWithUTF8String:v6ipsChars];
        v6ips = [v6ipsStr componentsSeparatedByString:@","];
    } else {
        v6ips = @[];
    }

    // 获取v6ttl
    int64_t v6ttl = sqlite3_column_int64(stmt, 10);

    // 获取v6LookupTime
    int64_t v6LookupTime = sqlite3_column_int64(stmt, 11);

    // 获取extra
    NSDictionary *extra = nil;
    const char *extraChars = (const char *)sqlite3_column_text(stmt, 12);
    if (extraChars) {
        NSString *extraStr = [NSString stringWithUTF8String:extraChars];
        NSData *jsonData = [extraStr dataUsingEncoding:NSUTF8StringEncoding];
        if (jsonData) {
            NSError *error = nil;
            id jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
            if (!error && [jsonObj isKindOfClass:[NSDictionary class]]) {
                extra = (NSDictionary *)jsonObj;
            }
        }
    }

    if (!extra) {
        extra = @{};
    }

    // 创建记录对象
    return [[HttpdnsHostRecord alloc] initWithId:recordId
                                        cacheKey:cacheKey
                                        hostName:hostName
                                        createAt:createAt
                                        modifyAt:modifyAt
                                        clientIp:clientIp
                                           v4ips:v4ips
                                           v4ttl:v4ttl
                                    v4LookupTime:v4LookupTime
                                           v6ips:v6ips
                                           v6ttl:v6ttl
                                    v6LookupTime:v6LookupTime
                                           extra:extra];
}

@end
