//
//  HttpdnsResult.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/5/15.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HttpdnsResult : NSObject

@property (nonatomic, copy) NSString *host;

@property (nonatomic, copy) NSArray<NSString *> *ips;
@property (nonatomic, copy) NSArray<NSString *> *ipv6s;

// 最后一次ipv4地址更新时间戳，Unix时间，单位秒
@property (nonatomic, assign) NSTimeInterval lastUpdatedTimeInterval;

// 最后一次ipv6地址更新时间戳，Unix时间，单位秒
@property (nonatomic, assign) NSTimeInterval v6LastUpdatedTimeInterval;

// 对应ipv4的ttl，单位秒
@property (nonatomic, assign) NSTimeInterval ttl;

// 对应ipv6的ttl，单位秒
@property (nonatomic, assign) NSTimeInterval v6ttl;

- (BOOL)hasIpv4Address;

- (BOOL)hasIpv6Address;

- (nullable NSString *)firstIpv4Address;

- (nullable NSString *)firstIpv6Address;

@end

NS_ASSUME_NONNULL_END
