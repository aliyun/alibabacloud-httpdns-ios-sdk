//
//  HttpdnsRequest.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/5/19.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsRequest.h"
#import "HttpdnsRequest_Internal.h"

static double const RESOLVE_HOST_DEFAULT_TIMEOUT_IN_SEC = 2;
static double const RESOLVE_HOST_MIN_TIMEOUT_IN_SEC = 0.5;
static double const RESOLVE_HOST_MAX_TIMEOUT_IN_SEC = 5;


@implementation HttpdnsRequest

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType {
    return [self initWithHost:host queryIpType:queryIpType sdnsParams:nil cacheKey:host];
}

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType sdnsParams:(NSDictionary<NSString *, NSString *> *)sdnsParams cacheKey:(NSString *)cacheKey {
    return [self initWithHost:host queryIpType:queryIpType sdnsParams:sdnsParams cacheKey:cacheKey resolveTimeout:RESOLVE_HOST_DEFAULT_TIMEOUT_IN_SEC];
}

- (instancetype)initWithHost:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIpType sdnsParams:(NSDictionary<NSString *,NSString *> *)sdnsParams cacheKey:(NSString *)cacheKey resolveTimeout:(double)timeoutInSecond {
    if (self = [super init]) {
        _host = host;
        _queryIpType = queryIpType;
        _sdnsParams = sdnsParams;

        if (cacheKey) {
            _cacheKey = cacheKey;
        } else {
            _cacheKey = host;
        }

        if (timeoutInSecond == 0) {
            timeoutInSecond = RESOLVE_HOST_DEFAULT_TIMEOUT_IN_SEC;
        } else if (timeoutInSecond < RESOLVE_HOST_MIN_TIMEOUT_IN_SEC) {
            timeoutInSecond = RESOLVE_HOST_MIN_TIMEOUT_IN_SEC;
        } else if (timeoutInSecond > RESOLVE_HOST_MAX_TIMEOUT_IN_SEC) {
            timeoutInSecond = RESOLVE_HOST_MAX_TIMEOUT_IN_SEC;
        } else {
            // 在范围内的正常值
        }
        _resolveTimeoutInSecond = timeoutInSecond;
    }
    return self;
}

- (void)setAsBlockingRequest {
    _isBlockingRequest = YES;
}

- (void)setAsNonBlockingRequest {
    _isBlockingRequest = NO;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Host: %@, isBlockingRequest: %d, queryIpType: %ld, sdnsParams: %@, cacheKey: %@", self.host, self.isBlockingRequest, self.queryIpType, self.sdnsParams, self.cacheKey];
}

@end
