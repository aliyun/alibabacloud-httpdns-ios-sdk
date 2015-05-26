//
//  HttpdnsTokenGen.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/26/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsTokenGen.h"

@implementation HttpdnsTokenGen

+(instancetype)sharedInstance {
    static dispatch_once_t _pred = 0;
    __strong static HttpdnsTokenGen * _httpDnsClient = nil;
    dispatch_once(&_pred, ^{
        _httpDnsClient = [[self alloc] init];
    });
    return _httpDnsClient;
}

@end
