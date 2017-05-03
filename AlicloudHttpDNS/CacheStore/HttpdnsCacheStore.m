//
//  HttpdnsCacheStore.m
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsCacheStore.h"
#import "HttpdnsPersistenceUtils.h"

@interface HttpdnsCacheStore()

@property (nonatomic, copy) NSString *accountId;

@end

@implementation HttpdnsCacheStore {
    LCDatabaseQueue *_databaseQueue;
}

+ (NSString *)databasePathWithName:(NSString *)name {
    return [HttpdnsPersistenceUtils hostCacheDatabasePathWithName:name];
}

- (instancetype)initWithAccountId:(NSString *)accountId {
    self = [super init];
    
    if (self) {
        _accountId = [accountId copy];
    }
    
    return self;
}

- (LCDatabaseQueue *)databaseQueue {
    @synchronized(self) {
        if (_databaseQueue) {
            return _databaseQueue;
        }
        
        if (self.accountId) {
            NSString *path = [[self class] databasePathWithName:self.accountId];
            _databaseQueue = [LCDatabaseQueue databaseQueueWithPath:path];
            
            if (_databaseQueue) {
                [self databaseQueueDidLoad];
            }
        }
    }
    
    return _databaseQueue;
}

- (void)databaseQueueDidLoad {
    // Stub
}

- (void)dealloc {
    [_databaseQueue close];
}

@end

