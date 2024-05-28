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

@property (nonatomic, strong) NSArray<NSString *> *ips;
@property (nonatomic, strong) NSArray<NSString *> *ipv6s;

// 最后一次更新时间戳，linux秒值
@property (nonatomic, assign) NSTimeInterval lastUpdatedTimeInterval;

// ttl，单位秒
@property (nonatomic, assign) NSTimeInterval ttl;

- (BOOL)hasIpv4Address;

- (BOOL)hasIpv6Address;

- (NSString *)firstIpv4Address;

- (NSString *)firstIpv6Address;

@end

NS_ASSUME_NONNULL_END
