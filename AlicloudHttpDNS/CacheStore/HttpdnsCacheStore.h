//
//  HttpdnsCacheStore.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>
#import "HttpdnsDB.h"

#ifdef DEBUG
#define ALICLOUD_HTTPDNS_SHOULD_LOG_ERRORS YES
#else
#define ALICLOUD_HTTPDNS_SHOULD_LOG_ERRORS NO
#endif

#define ALICLOUD_HTTPDNS_OPEN_DATABASE(db, routine) do {                \
      HttpdnsDatabaseQueue *dbQueue = [self databaseQueue];             \
                                                                        \
           [dbQueue inDatabase:^(HttpdnsDatabase *db) {                 \
                    db.logsErrors = ALICLOUD_HTTPDNS_SHOULD_LOG_ERRORS; \
                    routine;                                            \
                }];                                                     \
    } while (0)

@interface HttpdnsCacheStore : NSObject

@property (nonatomic, readonly, copy) NSString *accountId;

+ (NSString *)databasePathWithName:(NSString *)name;

- (HttpdnsDatabaseQueue *)databaseQueue;

- (void)databaseQueueDidLoad;

@end
