//
//  Dpa_Httpdns_iOS.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsService.h"
#import "HttpdnsLocalCache.h"
#import "HttpdnsModel.h"

@implementation HttpDnsService

+(instancetype)sharedInstance {
    static dispatch_once_t _pred = 0;
    __strong static HttpDnsService * _httpDnsClient = nil;
    dispatch_once(&_pred, ^{
        _httpDnsClient = [[self alloc] init];
    });
    return _httpDnsClient;
}

#pragma mark init

-(instancetype)init {
    NSMutableDictionary *cacheHosts = [HttpdnsLocalCache readFromLocalCache];
    _requestScheduler = [[HttpdnsRequestScheduler alloc] initWithCacheHosts:cacheHosts];
    return self;
}

#pragma mark dnsLookupMethods

-(void)setPreResolveHosts:(NSArray *)hosts {
    [_requestScheduler addPreResolveHosts:hosts];
}

-(NSString *)getIpByHost:(NSString *)host {
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host];
    if (hostObject) {
        NSMutableArray *ips = [hostObject getIps];
        if (ips && [ips count] > 0) {
            return [[ips objectAtIndex:0] getIpString];
        }
    }
    return nil;
}

@end