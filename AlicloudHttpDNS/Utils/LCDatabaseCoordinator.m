//
//  HttpdnsHostRecord.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "LCDatabaseCoordinator.h"
#import "LCDatabase.h"
#import "LCDatabaseQueue.h"
#import "HttpdnsLog.h"

#import <libkern/OSAtomic.h>

#ifdef DEBUG
#define LC_SHOULD_LOG_ERRORS YES
#else
#define LC_SHOULD_LOG_ERRORS NO
#endif

@interface LCDatabaseCoordinator () {
    LCDatabaseQueue *_dbQueue;
    OSSpinLock _dbQueueLock;
}

- (LCDatabaseQueue *)dbQueue;

@end

@implementation LCDatabaseCoordinator

- (instancetype)init {
    self = [super init];

    if (self) {
        _dbQueueLock = OS_SPINLOCK_INIT;
    }

    return self;
}

- (instancetype)initWithDatabasePath:(NSString *)databasePath {
    self = [super init];

    if (self) {
        _databasePath = [databasePath copy];
    }

    return self;
}

- (void)executeTransaction:(LCDatabaseJob)job fail:(LCDatabaseJob)fail {
    [self executeJob:^(LCDatabase *db) {
        [db beginTransaction];
        @try {
            job(db);
            [db commit];
        } @catch (NSException *exception) {
            [db rollback];
            fail(db);
        }
    }];
}

- (void)executeJob:(LCDatabaseJob)job {
    [self.dbQueue inDatabase:^(LCDatabase *db) {
        db.logsErrors = LC_SHOULD_LOG_ERRORS;
        job(db);
    }];
}

#pragma mark - Lazy loading

- (LCDatabaseQueue *)dbQueue {
    if (!_databasePath) {
        HttpdnsLogDebug("%@: Database path not found.", [[self class] description]);
        return nil;
    }

    OSSpinLockLock(&_dbQueueLock);

    if (!_dbQueue) {
        _dbQueue = [LCDatabaseQueue databaseQueueWithPath:_databasePath];
    }

    OSSpinLockUnlock(&_dbQueueLock);

    return _dbQueue;
}

#pragma mark -

- (void)dealloc {
    [_dbQueue close];
}

@end
