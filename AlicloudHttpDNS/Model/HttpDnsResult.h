//
//  HttpDnsResult.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/5/15.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HttpDnsResult : NSObject

@property (nonatomic, copy) NSString *host;
@property (nonatomic, strong) NSArray<NSString *> *ips;
@property (nonatomic, strong) NSArray<NSString *> *ipv6s;

- (BOOL)hasIpv4Address;

- (BOOL)hasIpv6Address;

- (NSString *)firstIpv4Address;

- (NSString *)firstIpv6Address;

@end

NS_ASSUME_NONNULL_END
