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
#import "HttpdnsUtil.h"

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
    NSDictionary *cacheHosts = [HttpdnsLocalCache readFromLocalCache];
    _requestScheduler = [[HttpdnsRequestScheduler alloc] init];
    [_requestScheduler readCacheHosts:cacheHosts];
    return self;
}

#pragma mark dnsLookupMethods

-(void)setPreResolveHosts:(NSArray *)hosts {
    [_requestScheduler addPreResolveHosts:hosts];
}

-(NSString *)getIpByHost:(NSString *)host {
    // 如果是ip，直接返回
    if ([HttpdnsUtil checkIfIsAnIp:host]) {
        HttpdnsLogDebug(@"[getIpByHost] - directly return this ip");
        return host;
    }
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host];
    if (hostObject) {
        NSArray *ips = [hostObject getIps];
        if (ips && [ips count] > 0) {
            return [[ips objectAtIndex:0] getIpString];
        }
    }
    HttpdnsLogDebug(@"[getIpByHost] - this host haven't exist in cache yet");
    return nil;
}

@end