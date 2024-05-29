//
//  HttpdnsRequest.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/5/19.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsRequest.h"

@implementation HttpdnsRequest

- (instancetype)initWithHost:(NSString *)host isBlockingRequest:(BOOL)isBlockingRequest queryIpType:(HttpdnsQueryIPType)queryIpType {
    return [self initWithHost:host isBlockingRequest:isBlockingRequest queryIpType:queryIpType sdnsParams:nil cacheKey:host];
}

- (instancetype)initWithHost:(NSString *)host isBlockingRequest:(BOOL)isBlockingRequest queryIpType:(HttpdnsQueryIPType)queryIpType sdnsParams:(NSDictionary<NSString *, NSString *> *)sdnsParams cacheKey:(NSString *)cacheKey {
    if (self = [super init]) {
        _host = host;
        _isBlockingRequest = isBlockingRequest;
        _queryIpType = queryIpType;
        _sdnsParams = sdnsParams;

        if (cacheKey) {
            _cacheKey = cacheKey;
        } else {
            _cacheKey = host;
        }
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Host: %@, isBlockingRequest: %d, queryIpType: %ld, sdnsParams: %@, cacheKey: %@", self.host, self.isBlockingRequest, self.queryIpType, self.sdnsParams, self.cacheKey];
}

@end
