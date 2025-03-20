//
//  HttpdnsLocalResolver.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/16.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsLocalResolver.h"

@implementation HttpdnsLocalResolver

+ (instancetype)sharedInstance {
    static HttpdnsLocalResolver *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HttpdnsLocalResolver alloc] init];
    });
    return instance;
}

- (HttpdnsHostObject *)resolve:(HttpdnsRequest *)request {
    // TODO
    return nil;
}

@end
