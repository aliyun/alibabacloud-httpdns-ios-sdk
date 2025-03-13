//
//  HttpdnsHostObjectInMemoryCache.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/9/28.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsHostObjectInMemoryCache.h"

@interface HttpdnsHostObjectInMemoryCache ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, HttpdnsHostObject *> *cacheDict;
@property (nonatomic, strong) NSLock *lock;

@end

@implementation HttpdnsHostObjectInMemoryCache

- (instancetype)init {
    self = [super init];
    if (self) {
        _cacheDict = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)setHostObject:(HttpdnsHostObject *)object forCacheKey:(NSString *)key {
    [_lock lock];
    _cacheDict[key] = object;
    [_lock unlock];
}

- (HttpdnsHostObject *)getHostObjectByCacheKey:(NSString *)key {
    [_lock lock];
    @try {
        HttpdnsHostObject *object = _cacheDict[key];
        return [object copy];
    } @finally {
        [_lock unlock];
    }
}

- (HttpdnsHostObject *)getHostObjectByCacheKey:(NSString *)key createIfNotExists:(HttpdnsHostObject *(^)(void))objectProducer {
    [_lock lock];
    HttpdnsHostObject *object = _cacheDict[key];
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

- (void)updateQualityForCacheKey:(NSString *)key forIp:(NSString *)ip withDetectRT:(NSInteger)detectRT {
    [_lock lock];
    HttpdnsHostObject *object = _cacheDict[key];
    if (object) {
        [object updateConnectedRT:detectRT forIP:ip];
    }
    [_lock unlock];
}

- (void)removeHostObjectByCacheKey:(NSString *)key {
    [_lock lock];
    [_cacheDict removeObjectForKey:key];
    [_lock unlock];
}

- (void)removeAllHostObjects {
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

- (NSArray *)allCacheKeys {
    [_lock lock];
    NSArray *keys = [_cacheDict allKeys];
    [_lock unlock];
    return keys;
}

@end
