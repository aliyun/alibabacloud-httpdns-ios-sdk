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
#import <AlicloudBeacon/AlicloudBeacon.h>
#import "HttpDnsHitService.h"
#import "HttpdnsConstants.h"

static NSDictionary *HTTPDNS_EXT_INFO = nil;
static dispatch_queue_t _authTimeOffsetSyncDispatchQueue = 0;

@interface HttpDnsService ()

@property (nonatomic, assign) int accountID;
@property (nonatomic, copy) NSString *secretKey;
/**
 * 每次访问的签名有效期，SDK内部定死，当前不暴露设置接口，有效期定为10分钟。
 */
@property (nonatomic, assign) NSUInteger authTimeoutInterval;

@end

@implementation HttpDnsService
@synthesize IPRankingDataSource = _IPRankingDataSource;

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _authTimeOffsetSyncDispatchQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.authTimeOffsetSyncDispatchQueue", DISPATCH_QUEUE_SERIAL);
    });
}

#pragma mark singleton

static HttpDnsService * _httpDnsClient = nil;

- (instancetype)initWithAccountID:(int)accountID {
    return [self initWithAccountID:accountID secretKey:nil];
}

//鉴权控制台：httpdns.console.aliyun.com
- (instancetype)initWithAccountID:(int)accountID secretKey:(NSString *)secretKey {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _httpDnsClient = [super init];
        _httpDnsClient.accountID = accountID;
        if ([HttpdnsUtil isValidString:secretKey]) {
            _httpDnsClient.secretKey = [secretKey copy];
        }
        NSString *accountIdString = [NSString stringWithFormat:@"%@", @(accountID)];
        [self shareInitWithAccountId:accountIdString];
    });
    return _httpDnsClient;
}

- (void)setAuthCurrentTime:(NSUInteger)authCurrentTime {
    dispatch_sync(_authTimeOffsetSyncDispatchQueue, ^{
        NSUInteger localTimeInterval = (NSUInteger)[[NSDate date] timeIntervalSince1970];
        _authTimeOffset = authCurrentTime - localTimeInterval;
    });
}

- (NSUInteger)authTimeOffset {
    __block NSUInteger authTimeOffset = 0;
    dispatch_sync(_authTimeOffsetSyncDispatchQueue, ^{
        authTimeOffset = _authTimeOffset;
    });
    return authTimeOffset;
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

- (void)shareInitWithAccountId:(NSString *)accountId {
    [_httpDnsClient requestScheduler];
    _httpDnsClient.timeoutInterval = HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL;
    HTTPDNS_EXT_INFO = @{
                         EXT_INFO_KEY_VERSION : HTTPDNS_IOS_SDK_VERSION,
                         };
    _httpDnsClient.authTimeoutInterval = HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL;
    
    

    
    /* 日活打点 */
    [[self class] statIfNeeded];//旧版日活打点
    [HttpDnsHitService setGlobalPropertyWithAccountId:accountId];
    [HttpDnsHitService bizActiveHit];//新版日活打点

    /* beacon */
    AlicloudBeaconService *beaconService =  [[AlicloudBeaconService alloc] initWithAppKey:HTTPDNS_BEACON_APPKEY appSecret:HTTPDNS_BEACON_APPSECRECT SDKVersion:HTTPDNS_IOS_SDK_VERSION SDKID:@"httpdns"];
    [beaconService enableLog:YES];
    [beaconService getBeaconConfigStringByKey:@"___httpdns_service___" completionHandler:^(NSString *result, NSError *error) {
        if ([HttpdnsUtil isValidString:result]) {
            HttpdnsLogDebug("%@", result);
            id jsonObj = [HttpdnsUtil convertJsonStringToObject:result];
            if ([HttpdnsUtil isValidDictionary:jsonObj]) {
                NSDictionary *serviceStatus = jsonObj;
                /* 检查打点开关 */
                NSString *utStatus = [serviceStatus objectForKey:@"ut"];
                if ([HttpdnsUtil isValidString:utStatus] && [utStatus isEqualToString:@"disabled"]) {
                    HttpdnsLogDebug(@"Beacon [___httpdns_service___] - [ut] is disabled, disable hit service.");
                    [HttpDnsHitService disableHitService];
                }
            }
        }
    }];

}

- (void)setAccountID:(int)accountID {
    _accountID = accountID;
    NSString *accountIdString = [NSString stringWithFormat:@"%@", @(accountID)];
    [self shareInitWithAccountId:accountIdString];
}

- (HttpdnsRequestScheduler *)requestScheduler {
    if (_requestScheduler) {
        return _requestScheduler;
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
    [HttpDnsHitService bizCacheEnable:enable];
}

- (void)setExpiredIPEnabled:(BOOL)enable {
    [_requestScheduler setExpiredIPEnabled:enable];
    [HttpDnsHitService bizExpiredIpEnable:enable];
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

- (void)setIPRankingDatasource:(NSDictionary<NSString *, NSNumber *> *)IPRankingDatasource {
    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), @"");
    _IPRankingDataSource = IPRankingDatasource;
}

- (NSDictionary *)IPRankingDataSource {
    NSDictionary *IPRankingDataSource = nil;
    @synchronized(self) {
        if ([HttpdnsUtil isValidDictionary:_IPRankingDataSource]) {
            IPRankingDataSource = _IPRankingDataSource;
        }
    }
    return IPRankingDataSource;
}

@end
