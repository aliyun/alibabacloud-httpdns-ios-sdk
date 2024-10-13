//
//  HttpdnsThreadSafeDictionary.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/9/28.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsThreadSafeDictionary.h"

@interface HttpdnsThreadSafeDictionary ()

@property (nonatomic, strong) NSMutableDictionary *cacheDict;
@property (nonatomic, strong) NSLock *lock;

@end

@implementation HttpdnsThreadSafeDictionary

- (instancetype)init {
    self = [super init];
    if (self) {
        _cacheDict = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)setObject:(id)object forKey:(NSString *)key {
    [_lock lock];
    _cacheDict[key] = object;
    [_lock unlock];
}

- (id)objectForKey:(NSString *)key {
    [_lock lock];
    @try {
        id object = _cacheDict[key];
        return [object copy];
    } @finally {
        [_lock unlock];
    }
}

- (id)getObjectForKey:(NSString *)key createIfNotExists:(id (^)(void))objectProducer {
    [_lock lock];
    id object = _cacheDict[key];
    @try {
        if (!object) {
            object = objectProducer();
            _cacheDict[key] = object;
        }
        return [object copy];
    } @finally {
        [_lock unlock];
    }
}

- (void)removeObjectForKey:(NSString *)key {
    [_lock lock];
    [_cacheDict removeObjectForKey:key];
    [_lock unlock];
}

- (void)removeAllObjects {
    [_lock lock];
    [_cacheDict removeAllObjects];
    [_lock unlock];
}

- (NSInteger)count {
    [_lock lock];
    NSInteger count = _cacheDict.count;
    [_lock unlock];
    return count;
}

- (NSArray *)allKeys {
    [_lock lock];
    NSArray *keys = [_cacheDict allKeys];
    [_lock unlock];
    return keys;
}

@end
