//
//  HttpdnsCacheStore.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsCacheStore.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsServiceProvider.h"

@interface HttpdnsCacheStore()

@property (nonatomic, copy) NSString *accountId;

@end

@implementation HttpdnsCacheStore {
    HttpdnsDatabaseQueue *_databaseQueue;
}

+ (NSString *)databasePathWithName:(NSString *)name {
    return [HttpdnsPersistenceUtils hostCacheDatabasePathWithName:name];
}

- (instancetype)init {
    self = [super init];
    
    if (self) {
        HttpDnsService *sharedService = [HttpDnsService sharedInstance];
        _accountId = [NSString stringWithFormat:@"%@", @(sharedService.accountID)];
    }
    
    return self;
}

- (HttpdnsDatabaseQueue *)databaseQueue {
    @synchronized(self) {
        if (_databaseQueue) {
            return _databaseQueue;
        }
        
        if (self.accountId) {
            NSString *path = [[self class] databasePathWithName:self.accountId];
            _databaseQueue = [HttpdnsDatabaseQueue databaseQueueWithPath:path];
            
            if (_databaseQueue) {
                [self databaseQueueDidLoad];
            }
        }
    }
    
    return _databaseQueue;
}

- (void)databaseQueueDidLoad {
    // Stub
    // This enforces implementing this method in subclasses
    [self doesNotRecognizeSelector:_cmd];
}

- (void)dealloc {
    [_databaseQueue close];
}

@end

