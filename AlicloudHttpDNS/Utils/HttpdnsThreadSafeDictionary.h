//
//  HttpdnsThreadSafeDictionary.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/9/28.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 这个字典在HTTPDNS中只用于存储HttpdnsHostObject对象，这个对象是整个框架的核心对象，用于缓存和处理域名解析结果
// 通常从缓存中获得这个对象之后，会根据不同场景改变一些字段的值，而且很可能发生在不同线程中
// 而不同线程从缓存中直接读取共享对象的话，很有可能发生线程竞争的情况，多线程访问某个对象的同一个字段，在swift环境有较高概率发生crash
// 因此，除了确保字典操作的线程安全，拿出对象的时候，也直接copy一个复制对象返回(HttpdnsHostObject对象实现了NSCopying协议)
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
