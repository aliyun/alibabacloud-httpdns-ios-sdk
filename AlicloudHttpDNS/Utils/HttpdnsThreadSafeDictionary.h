//
//  HttpdnsThreadSafeDictionary.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/9/28.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HttpdnsThreadSafeDictionary : NSObject

- (void)setObject:(id)object forKey:(NSString *)key;

- (id)objectForKey:(NSString *)key;

- (id)getObjectForKey:(NSString *)key createIfNotExists:(id (^)(void))objectProducer;

- (void)removeObjectForKey:(NSString *)key;

- (void)removeAllObjects;

- (NSInteger)count;

- (NSArray *)allKeys;

@end

NS_ASSUME_NONNULL_END
