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

#import "HttpdnsRequestScheduler.h"
#import "HttpdnsServiceProvider.h"
#import "HttpdnsRequest.h"
#import "HttpdnsModel.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"

@implementation HttpDnsService {
    HttpdnsRequestScheduler *_requestScheduler;
}

#pragma mark singleton

+(instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static HttpDnsService * _httpDnsClient = nil;
    dispatch_once(&onceToken, ^{
        _httpDnsClient = [[super allocWithZone:NULL] init];
    });
    return _httpDnsClient;
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
        NSDictionary *cachedHosts = [HttpdnsLocalCache readFromLocalCache];
        _requestScheduler = [[HttpdnsRequestScheduler alloc] init];
        [_requestScheduler readCachedHosts:cachedHosts];
    }
    return self;
}

#pragma mark dnsLookupMethods

-(void)setPreResolveHosts:(NSArray *)hosts {
    [_requestScheduler addPreResolveHosts:hosts];
}

-(NSString *)getIpByHost:(NSString *)host {
    
    if ([self.delegate shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return host;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP.");
        return host;
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        return nil;
    }
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host synchronously:YES];
    if (hostObject) {
        NSArray * ips = [hostObject getIps];
        if (ips && [ips count] > 0) {
            return [ips[0] getIpString];
        }
    }
    return nil;
}

-(NSString *)getIpByHostAsync:(NSString *)host {
    
    if ([self.delegate shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return host;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP.");
        return host;
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        return nil;
    }
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host synchronously:NO];
    if (hostObject) {
        NSArray *ips = [hostObject getIps];
        if (ips && [ips count] > 0) {
            return [[ips objectAtIndex:0] getIpString];
        }
    }
    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;
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

@end