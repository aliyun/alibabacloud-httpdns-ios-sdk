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

/// 需要解析的域名
@property (nonatomic, copy) NSString *host;

/// 解析超时时间，对于同步接口，即为最大等待时间，对于异步接口，即为最大等待回调时间
@property (nonatomic, assign) double resolveTimeoutInSecond;

/// 查询IP类型
/// 默认为HttpdnsQueryIPTypeAuto，此类型下，SDK至少会请求解析ipv4地址，若判断到当前网络环境支持ipv6，则还会请求解析ipv6地址
/// HttpdnsQueryIPTypeIpv4，只请求解析ipv4
/// HttpdnsQueryIPTypeIpv6，只请求解析ipv6
/// HttpdnsQueryIPTypeBoth，不管当前网络环境是什么，会尝试同时请求解析ipv4地址和ipv6地址，这种用法，通常需要拿到结果之后自行判断网络环境决定使用哪个结果
@property (nonatomic, assign) HttpdnsQueryIPType queryIpType;

/// SDNS参数，针对软件自定义解析场景使用
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *sdnsParams;

/// 缓存Key，针对软件自定义解析场景使用
@property (nonatomic, copy, nullable) NSString *cacheKey;

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType;

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType sdnsParams:(nullable NSDictionary<NSString *, NSString *> *)sdnsParams cacheKey:(nullable NSString *)cacheKey;

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType sdnsParams:(nullable NSDictionary<NSString *, NSString *> *)sdnsParams cacheKey:(nullable NSString *)cacheKey resolveTimeout:(double)timeoutInSecond;

@end

NS_ASSUME_NONNULL_END
