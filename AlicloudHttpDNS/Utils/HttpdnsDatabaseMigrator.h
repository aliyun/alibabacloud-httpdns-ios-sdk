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


#import <Foundation/Foundation.h>
#import "HttpdnsDatabaseCommon.h"

/*!
 * Database migration object.
 */
@interface HttpdnsDatabaseMigration : NSObject

/*!
 * The job of current migration.
 */
@property (readonly) HttpdnsDatabaseJob block;

+ (instancetype)migrationWithBlock:(HttpdnsDatabaseJob)block;

- (instancetype)initWithBlock:(HttpdnsDatabaseJob)block;

@end

/*!
 * SQLite database migrator.
 */
@interface HttpdnsDatabaseMigrator : NSObject

@property (readonly) NSString *databasePath;

- (instancetype)initWithDatabasePath:(NSString *)databasePath;

/*!
 * Migrate database with migrations.
 * @param migrations An array of object confirms HttpdnsDatabaseMigration protocol.
 * NOTE: migration can not be removed, only can be added.
 * @return void.
 */
- (void)executeMigrations:(NSArray *)migrations;

@end
