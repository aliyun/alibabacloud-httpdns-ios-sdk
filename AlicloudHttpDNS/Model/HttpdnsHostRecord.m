//
//  HttpdnsHostRecord.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsHostRecord.h"
#import "HttpdnsUtil.h"

@interface HttpdnsHostRecord()

@property (nonatomic, assign) NSUInteger id;

@property (nonatomic, copy) NSString *cacheKey;

@property (nonatomic, copy) NSString *hostName;

@property (nonatomic, strong) NSDate *createAt;

@property (nonatomic, strong) NSDate *modifyAt;

@property (nonatomic, copy) NSString *clientIp;

@property (nonatomic, copy) NSArray<NSString *> *v4ips;

@property (nonatomic, assign) int64_t v4ttl;

@property (nonatomic, assign) int64_t v4LookupTime;

@property (nonatomic, copy) NSArray<NSString *> *v6ips;

@property (nonatomic, assign) int64_t v6ttl;

@property (nonatomic, assign) int64_t v6LookupTime;

@property (nonatomic, copy) NSDictionary *extra;

@end


@implementation HttpdnsHostRecord

- (instancetype)initWithId:(NSUInteger)id
                  cacheKey:(NSString *)cacheKey
                  hostName:(NSString *)hostName
                  createAt:(NSDate *)createAt
                  modifyAt:(NSDate *)modifyAt
                  clientIp:(NSString *)clientIp
                     v4ips:(NSArray<NSString *> *)v4ips
                     v4ttl:(int64_t)v4ttl
              v4LookupTime:(int64_t)v4LookupTime
                     v6ips:(NSArray<NSString *> *)v6ips
                     v6ttl:(int64_t)v6ttl
              v6LookupTime:(int64_t)v6LookupTime
                     extra:(NSDictionary *)extra {
    self = [super init];
    if (self) {
        _id = id;
        _cacheKey = [cacheKey copy];
        _hostName = [hostName copy];
        _createAt = createAt;
        _modifyAt = modifyAt;
        _clientIp = [clientIp copy];
        _v4ips = [v4ips copy] ?: @[];
        _v4ttl = v4ttl;
        _v4LookupTime = v4LookupTime;
        _v6ips = [v6ips copy] ?: @[];
        _v6ttl = v6ttl;
        _v6LookupTime = v6LookupTime;
        _extra = [extra copy] ?: @{};
    }
    return self;
}

- (NSString *)description {
    NSString *hostName = self.hostName;
    if (self.cacheKey) {
        hostName = [NSString stringWithFormat:@"%@(%@)", hostName, self.cacheKey];
    }
    if ([HttpdnsUtil isEmptyArray:_v6ips]) {
        return [NSString stringWithFormat:@"hostName = %@, v4ips = %@, v4ttl = %lld v4LastLookup = %lld extra = %@",
                hostName, _v4ips, _v4ttl, _v4LookupTime, _extra];
    } else {
        return [NSString stringWithFormat:@"hostName = %@, v4ips = %@, v4ttl = %lld v4LastLookup = %lld v6ips = %@ v6ttl = %lld v6LastLookup = %lld extra = %@",
                hostName, _v4ips, _v4ttl, _v4LookupTime, _v6ips, _v6ttl, _v6LookupTime, _extra];
    }
}

@end
