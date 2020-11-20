//
//  HttpdnsKeyValueStore.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HttpdnsKeyValueStore : NSObject

+ (instancetype)sharedInstance;

- (instancetype)initWithDatabasePath:(NSString *)databasePath;

- (instancetype)initWithDatabasePath:(NSString *)databasePath tableName:(NSString *)tableName;

- (NSData *)dataForKey:(NSString *)key;

- (void)setData:(NSData *)data forKey:(NSString *)key;

- (void)deleteKey:(NSString *)key;

@end
