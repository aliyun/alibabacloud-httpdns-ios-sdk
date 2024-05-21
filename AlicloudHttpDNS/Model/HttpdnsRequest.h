//
//  HttpdnsRequest.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/5/19.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsService.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpdnsRequest : NSObject

@property (nonatomic, copy) NSString *host;

@property (nonatomic, assign) BOOL isBlockingRequest;

@property (nonatomic, assign) HttpdnsQueryIPType queryIpType;

@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *sdnsParams;

@property (nonatomic, copy, nullable) NSString *cacheKey;

- (instancetype)initWithHost:(NSString *)host isBlockingRequest:(BOOL)isBlockingRequest queryIpType:(HttpdnsQueryIPType)queryIpType;

- (instancetype)initWithHost:(NSString *)host isBlockingRequest:(BOOL)isBlockingRequest queryIpType:(HttpdnsQueryIPType)queryIpType sdnsParams:(nullable NSDictionary<NSString *, NSString *> *)sdnsParams cacheKey:(nullable NSString *)cacheKey;

@end

NS_ASSUME_NONNULL_END
