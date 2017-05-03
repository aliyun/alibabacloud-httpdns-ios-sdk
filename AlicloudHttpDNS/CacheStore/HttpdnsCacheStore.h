//
//  HttpdnsCacheStore.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>
#import "LCDB.h"

#ifdef DEBUG
#define LCIM_SHOULD_LOG_ERRORS YES
#else
#define LCIM_SHOULD_LOG_ERRORS NO
#endif

#define LCIM_OPEN_DATABASE(db, routine) do {    \
LCDatabaseQueue *dbQueue = [self databaseQueue]; \
                                                 \
    [dbQueue inDatabase:^(LCDatabase *db) {     \
        db.logsErrors = LCIM_SHOULD_LOG_ERRORS; \
        routine;                                \
    }];                                         \
} while (0)

@interface HttpdnsCacheStore : NSObject

@property (nonatomic, readonly, copy) NSString *accountId;

+ (NSString *)databasePathWithName:(NSString *)name;

- (instancetype)initWithAccountId:(NSString *)accountId;

- (LCDatabaseQueue *)databaseQueue;

- (void)databaseQueueDidLoad;

@end
