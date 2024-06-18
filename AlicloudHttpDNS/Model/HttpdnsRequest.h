//
//  HttpdnsRequest.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/5/19.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum {
    AlicloudHttpDNS_IPTypeV4     = 0,            //ipv4
    AlicloudHttpDNS_IPTypeV6     = 1,            //ipv6
    AlicloudHttpDNS_IPTypeV64    = 2,            //ipv4 + ipv6
} AlicloudHttpDNS_IPType;

typedef NS_OPTIONS(NSUInteger, HttpdnsQueryIPType) {
    HttpdnsQueryIPTypeAuto = 0 << 0,
    HttpdnsQueryIPTypeIpv4 = 1 << 0,
    HttpdnsQueryIPTypeIpv6 = 1 << 1,
    HttpdnsQueryIPTypeBoth = HttpdnsQueryIPTypeIpv4 | HttpdnsQueryIPTypeIpv6,
};

@interface HttpdnsRequest : NSObject

@property (nonatomic, copy) NSString *host;

@property (nonatomic, assign) double resolveTimeoutInSecond;

@property (nonatomic, assign) HttpdnsQueryIPType queryIpType;

@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *sdnsParams;

@property (nonatomic, copy, nullable) NSString *cacheKey;

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType;

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType sdnsParams:(nullable NSDictionary<NSString *, NSString *> *)sdnsParams cacheKey:(nullable NSString *)cacheKey;

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType sdnsParams:(nullable NSDictionary<NSString *, NSString *> *)sdnsParams cacheKey:(nullable NSString *)cacheKey resolveTimeout:(double)timeoutInSecond;

@end

NS_ASSUME_NONNULL_END
