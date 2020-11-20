//
//  HttpdnsHostRecord.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsDatabaseCoordinator.h"
#import "HttpdnsDatabase.h"
#import "HttpdnsDatabaseQueue.h"
#import "HttpdnsLog_Internal.h"

#import <libkern/OSAtomic.h>

#ifdef DEBUG
#define ALICLOUD_HTTPDNS_SHOULD_LOG_ERRORS YES
#else
#define ALICLOUD_HTTPDNS_SHOULD_LOG_ERRORS NO
#endif

@interface HttpdnsDatabaseCoordinator () {
    HttpdnsDatabaseQueue *_dbQueue;
    OSSpinLock _dbQueueLock;
}

- (HttpdnsDatabaseQueue *)dbQueue;

@end

@implementation HttpdnsDatabaseCoordinator

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

- (void)executeTransaction:(HttpdnsDatabaseJob)job fail:(HttpdnsDatabaseJob)fail {
    [self executeJob:^(HttpdnsDatabase *db) {
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

- (void)executeJob:(HttpdnsDatabaseJob)job {
    [self.dbQueue inDatabase:^(HttpdnsDatabase *db) {
        db.logsErrors = ALICLOUD_HTTPDNS_SHOULD_LOG_ERRORS;
        job(db);
    }];
}

#pragma mark - Lazy loading

- (HttpdnsDatabaseQueue *)dbQueue {
    if (!_databasePath) {
        HttpdnsLogDebug("%@: Database path not found.", [[self class] description]);
        return nil;
    }

    OSSpinLockLock(&_dbQueueLock);

    if (!_dbQueue) {
        _dbQueue = [HttpdnsDatabaseQueue databaseQueueWithPath:_databasePath];
    }

    OSSpinLockUnlock(&_dbQueueLock);

    return _dbQueue;
}

#pragma mark -

- (void)dealloc {
    [_dbQueue close];
}

@end
