/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsRequest.h"
#import "HttpdnsConfig.h"
#import "HttpdnsModel.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"
#import <AlicloudUtils/AlicloudUtils.h>
#import "AlicloudHttpDNS.h"
#import "HttpdnsHostCacheStore.h"

static NSDictionary *HTTPDNS_EXT_INFO = nil;

@interface HttpDnsService ()

@property (nonatomic, assign) int accountID;

@end

@implementation HttpDnsService

#pragma mark singleton

<<<<<<< HEAD
+ (instancetype)sharedInstance {
=======

#pragma mark init
static HttpDnsService * _httpDnsClient = nil;

- (instancetype)initWithAccountID:(int)accountID {
>>>>>>> 31ef7c1... inhance securement to avoid json crash
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _httpDnsClient = [super init];
        _httpDnsClient.accountID = accountID;
        [self shareInit];
    });
    return _httpDnsClient;
}

+(instancetype)sharedInstance {
    return [[self alloc] init];
}

+ (void)statIfNeeded {
    [AlicloudReport statAsync:AMSHTTPDNS extInfo:HTTPDNS_EXT_INFO];
}

+ (id)allocWithZone:(NSZone *)zone {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _httpDnsClient = [super allocWithZone:zone];
    });
    return _httpDnsClient;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (void)shareInit {
    [_httpDnsClient requestScheduler];
    _httpDnsClient.timeoutInterval = HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL;
    HTTPDNS_EXT_INFO = @{
                         EXT_INFO_KEY_VERSION : HTTPDNS_IOS_SDK_VERSION,
                         };
    [[self class] statIfNeeded];
}

- (void)setAccountID:(int)accountID {
    _accountID = accountID;
    [self shareInit];
}

<<<<<<< HEAD
- (instancetype)init {
    if (self = [super init]) {
        _requestScheduler = [[HttpdnsRequestScheduler alloc] init];
=======
- (HttpdnsRequestScheduler *)requestScheduler {
    if (_requestScheduler) {
        return _requestScheduler;
>>>>>>> 31ef7c1... inhance securement to avoid json crash
    }
    HttpdnsRequestScheduler *requestScheduler = [[HttpdnsRequestScheduler alloc] init];
    _requestScheduler = requestScheduler;
    return _requestScheduler;
}

#pragma mark dnsLookupMethods

- (void)setPreResolveHosts:(NSArray *)hosts {
    [_requestScheduler addPreResolveHosts:hosts];
}

- (NSString *)getIpByHost:(NSString *)host {
    NSArray *ips = [self getIpsByHost:host];
    if (ips != nil && ips.count > 0) {
        NSString *ip;
        @try {
            ip = ips[0];
        } @catch (NSException *exception) {}
        return ip;
    }
    return nil;
}

- (NSArray *)getIpsByHost:(NSString *)host {
    if ([self.delegate shouldDegradeHTTPDNS:host]) {
        return nil;
    }
    
    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP.");
        return [NSArray arrayWithObjects:host, nil];
    }
    
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        return nil;
    }
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host synchronously:YES];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        if (ipsObject && [ipsObject count] > 0) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                @try {
                    [ipsArray addObject:[ipObject getIpString]];
                } @catch (NSException *exception) {}
            }
            return ipsArray;
        }
    }
    return nil;

}

- (NSString *)getIpByHostInURLFormat:(NSString *)host {
    NSString *IP = [self getIpByHost:host];
    if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:IP]) {
        return [NSString stringWithFormat:@"[%@]", IP];
    }
    return IP;
}

- (NSString *)getIpByHostAsync:(NSString *)host {
    NSArray *ips = [self getIpsByHostAsync:host];
    if (ips != nil && ips.count > 0) {
        NSString *ip;
        @try {
            ip = ips[0];
        } @catch (NSException *exception) {}
        return ip;
    }
    return nil;
}

- (NSArray *)getIpsByHostAsync:(NSString *)host {
    if ([self.delegate shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }
    
    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP.");
        return [NSArray arrayWithObjects:host, nil];
    }
    
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        return nil;
    }
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host synchronously:NO];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        if (ipsObject && [ipsObject count] > 0) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                [ipsArray addObject:[ipObject getIpString]];
            }
            return ipsArray;
        }
    }
    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;

}

- (NSString *)getIpByHostAsyncInURLFormat:(NSString *)host {
    NSString *IP = [self getIpByHostAsync:host];
    if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:IP]) {
        return [NSString stringWithFormat:@"[%@]", IP];
    }
    return IP;
}

- (void)setHTTPSRequestEnabled:(BOOL)enable {
    HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED = enable;
}

- (void)setCachedIPEnabled:(BOOL)enable {
    [_requestScheduler setCachedIPEnabled:enable];
}

- (void)setExpiredIPEnabled:(BOOL)enable {
    [_requestScheduler setExpiredIPEnabled:enable];
}

- (void)setLogEnabled:(BOOL)enable {
    if (enable) {
        [HttpdnsLog enableLog];
    } else {
        [HttpdnsLog disableLog];
    }
}

- (void)setPreResolveAfterNetworkChanged:(BOOL)enable {
    [_requestScheduler setPreResolveAfterNetworkChanged:enable];
}

@end
