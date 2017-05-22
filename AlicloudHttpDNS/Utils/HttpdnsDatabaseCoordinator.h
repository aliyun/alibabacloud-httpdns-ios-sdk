//
//  HttpdnsHostRecord.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsDatabaseCommon.h"

@interface HttpdnsDatabaseCoordinator : NSObject

@property (readonly) NSString *databasePath;

- (instancetype)initWithDatabasePath:(NSString *)databasePath;

- (void)executeTransaction:(HttpdnsDatabaseJob)job fail:(HttpdnsDatabaseJob)fail;

- (void)executeJob:(HttpdnsDatabaseJob)job;

@end
