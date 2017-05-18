/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */


#import "HttpdnsDatabaseMigrator.h"
#import "HttpdnsDatabaseCoordinator.h"
#import "HttpdnsDatabase.h"
#import "HttpdnsDatabaseAdditions.h"

#import <libkern/OSAtomic.h>

@interface HttpdnsDatabaseMigrator () {
    HttpdnsDatabaseCoordinator *_coordinator;
    OSSpinLock _coordinatorLock;
}

@property (readonly) HttpdnsDatabaseCoordinator *coordinator;

@end

@implementation HttpdnsDatabaseMigrator

- (instancetype)init {
    self = [super init];

    if (self) {
        _coordinatorLock = OS_SPINLOCK_INIT;
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

- (NSInteger)versionOfDatabase {
    __block NSInteger version = 0;

    [self.coordinator executeJob:^(HttpdnsDatabase *db) {
        version = (NSInteger)[db userVersion];
    }];

    return version;
}

- (void)applyMigrations:(NSArray *)migrations
            fromVersion:(uint32_t)fromVersion
               database:(HttpdnsDatabase *)database
{
    for (HttpdnsDatabaseMigration *migration in migrations) {
        if (migration.block) {
            migration.block(database);
        }

        [database setUserVersion:++fromVersion];
    }
}

- (void)executeMigrations:(NSArray *)migrations {
    uint32_t newVersion = (uint32_t)[migrations count];
    uint32_t oldVersion = (uint32_t)[self versionOfDatabase];

    if (oldVersion < newVersion) {
        NSArray *restMigrations = [migrations subarrayWithRange:NSMakeRange(oldVersion, newVersion - oldVersion)];

        [self.coordinator
         executeTransaction:^(HttpdnsDatabase *db) {
             [self applyMigrations:restMigrations fromVersion:oldVersion database:db];
         }
         fail:^(HttpdnsDatabase *db) {
             [db setUserVersion:oldVersion];
         }];
    }
}

#pragma mark - Lazy loading

- (HttpdnsDatabaseCoordinator *)coordinator {
    OSSpinLockLock(&_coordinatorLock);

    if (!_coordinator) {
        _coordinator = [[HttpdnsDatabaseCoordinator alloc] initWithDatabasePath:_databasePath];
    }

    OSSpinLockUnlock(&_coordinatorLock);

    return _coordinator;
}

@end

@implementation HttpdnsDatabaseMigration

+ (instancetype)migrationWithBlock:(HttpdnsDatabaseJob)block {
    return [[self alloc] initWithBlock:block];
}

- (instancetype)initWithBlock:(HttpdnsDatabaseJob)block {
    self = [super init];

    if (self) {
        _block = [block copy];
    }

    return self;
}

@end
