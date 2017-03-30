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

#import "HttpdnsServiceProvider.h"
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsRequest.h"
#import "HttpdnsConfig.h"
#import "HttpdnsModel.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"
#import <AlicloudUtils/AlicloudUtils.h>
#import "HttpdnsServiceProvider_Internal.h"
#import "AlicloudHttpDNS.h"

static NSDictionary * HTTPDNS_EXT_INFO = nil;

@implementation HttpDnsService

#pragma mark singleton

+(instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static HttpDnsService * _httpDnsClient = nil;
    dispatch_once(&onceToken, ^{
        _httpDnsClient = [[super allocWithZone:NULL] init];
        _httpDnsClient.timeoutInterval = HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL;
        HTTPDNS_EXT_INFO = @{
                             EXT_INFO_KEY_VERSION : HTTPDNS_IOS_SDK_VERSION,
                             };
        [self statIfNeeded];
    });
    return _httpDnsClient;
}

+ (void)statIfNeeded {
    [AlicloudReport statAsync:AMSHTTPDNS extInfo:HTTPDNS_EXT_INFO];
}

+ (id)allocWithZone:(NSZone *)zone {
    return [self sharedInstance];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

#pragma mark init

-(instancetype)init {
    if (self = [super init]) {
        _requestScheduler = [[HttpdnsRequestScheduler alloc] init];
    }
    return self;
}

#pragma mark dnsLookupMethods

-(void)setPreResolveHosts:(NSArray *)hosts {
    [_requestScheduler addPreResolveHosts:hosts];
}

-(NSString *)getIpByHost:(NSString *)host {
    NSArray *ips = [self getIpsByHost:host];
    if (ips != nil && ips.count > 0) {
        return ips[0];
    }
    return nil;
}

- (NSArray *)getIpsByHost:(NSString *)host {
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
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host synchronously:YES];
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
    return nil;

}

- (NSString *)getIpByHostInURLFormat:(NSString *)host {
    NSString *IP = [self getIpByHost:host];
    if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:IP]) {
        return [NSString stringWithFormat:@"[%@]", IP];
    }
    return IP;
}

-(NSString *)getIpByHostAsync:(NSString *)host {
    NSArray *ips = [self getIpsByHostAsync:host];
    if (ips != nil && ips.count > 0) {
        return ips[0];
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

-(void)setExpiredIPEnabled:(BOOL)enable {
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
