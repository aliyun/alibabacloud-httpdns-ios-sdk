//
//  Dpa_Httpdns_iOS.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsRequestScheduler.h"
#import "HttpdnsServiceProvider.h"
#import "HttpdnsRequest.h"
#import "HttpdnsModel.h"
#import "HttpdnsUtil.h"
#import "NetworkDetection.h"
#import "HttpdnsLog.h"

@implementation HttpDnsServiceProvider

NetworkDetection* reachability;

+(instancetype)sharedInstance {
    static dispatch_once_t once;
    static HttpDnsServiceProvider * _httpDnsClient = nil;
    dispatch_once(&once, ^{
        _httpDnsClient = [[self alloc] init];
    });
    return _httpDnsClient;
}

+(instancetype)getService {
    return [HttpDnsServiceProvider sharedInstance];
}

#pragma mark init

-(instancetype)init {
    NSDictionary *cacheHosts = [HttpdnsLocalCache readFromLocalCache];
    _requestScheduler = [[HttpdnsRequestScheduler alloc] init];
    [_requestScheduler readCacheHosts:cacheHosts];

    dispatch_async(dispatch_get_main_queue(), ^{
        HttpdnsLogDebug("[dispatch_async] - Current thread: %@", [NSThread currentThread]);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNetworkChange:) name:kReachabilityChangedNotification object:nil];
        reachability = [NetworkDetection reachabilityForInternetConnection];
        [reachability startNotifier];
    });
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [HttpdnsRequest requestServerTimeStamp];
    });
    return self;
}

#pragma mark dnsLookupMethods

-(void)setPreResolveHosts:(NSArray *)hosts {
    [_requestScheduler addPreResolveHosts:hosts];
}

-(NSString *)getIpByHost:(NSString *)host {

    if (!host) {
        return host;
    }

    // 如果是ip，直接返回
    if ([HttpdnsUtil checkIfIsAnIp:host]) {
        HttpdnsLogDebug(@"[getIpByHost] - directly return this ip");
        return host;
    }
    // 判断host是否合法
    if (![HttpdnsUtil checkIfIsAnHost:host]) {
        HttpdnsLogDebug(@"[getIpByHost] - the host is illegal ,directly return nil");
        return nil;
    }
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookupSync:host];
    if (hostObject) {
        NSArray * ips = [hostObject getIps];
        if (ips && [ips count] > 0) {
            return [ips[0] getIpString];
        }
    }
    return nil;
}

-(NSString *)getIpByHostAsync:(NSString *)host {

    if (!host) {
        return host;
    }

    // 如果是ip，直接返回
    if ([HttpdnsUtil checkIfIsAnIp:host]) {
        HttpdnsLogDebug(@"[getIpByHost] - directly return this ip");
        return host;
    }
    // 判断host是否合法
    if (![HttpdnsUtil checkIfIsAnHost:host]) {
        HttpdnsLogDebug(@"[getIpByHost] - the host is illegal ,directly return nil");
        return nil;
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

- (void)handleNetworkChange:(NSNotification *)notice {
    NetworkStatus remoteHostStatus = [reachability currentReachabilityStatus];
    [_requestScheduler resetAfterNetworkChanged];
    if (remoteHostStatus == NotReachable) {
        HttpdnsLogDebug("[handleNetworkChange] - no networking");
    } else if (remoteHostStatus == ReachableViaWiFi) {
        HttpdnsLogDebug("[handleNetworkChange] - wifi");
    } else if (remoteHostStatus == ReachableViaWWAN) {
        HttpdnsLogDebug("[handleNetworkChange] - cell");
    } else {
        HttpdnsLogError("[handleNetworkChange] - unknown type: %d", (int)remoteHostStatus);
    }
}
@end