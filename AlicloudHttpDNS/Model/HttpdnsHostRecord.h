//
//  HttpdnsHostRecord.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HttpdnsHostRecord : NSObject

@property (nonatomic, assign, readonly) NSUInteger id;

@property (nonatomic, copy, readonly) NSString *cacheKey;

@property (nonatomic, copy, readonly) NSString *hostName;

@property (nonatomic, strong, readonly) NSDate *createAt;

@property (nonatomic, strong, readonly) NSDate *modifyAt;

@property (nonatomic, copy, readonly) NSString *clientIp;

@property (nonatomic, copy, readonly) NSArray<NSString *> *v4ips;

@property (nonatomic, assign, readonly) int64_t v4ttl;

@property (nonatomic, assign, readonly) int64_t v4LookupTime;

@property (nonatomic, copy, readonly) NSArray<NSString *> *v6ips;

@property (nonatomic, assign, readonly) int64_t v6ttl;

@property (nonatomic, assign, readonly) int64_t v6LookupTime;

@property (nonatomic, copy, readonly) NSDictionary *extra;

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
                    extra:(NSDictionary *)extra;

@end
