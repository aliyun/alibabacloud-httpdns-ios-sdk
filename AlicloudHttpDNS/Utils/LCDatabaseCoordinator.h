//
//  HttpdnsHostRecord.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LCDatabaseCommon.h"

@interface LCDatabaseCoordinator : NSObject

@property (readonly) NSString *databasePath;

- (instancetype)initWithDatabasePath:(NSString *)databasePath;

- (void)executeTransaction:(LCDatabaseJob)job fail:(LCDatabaseJob)fail;

- (void)executeJob:(LCDatabaseJob)job;

@end
