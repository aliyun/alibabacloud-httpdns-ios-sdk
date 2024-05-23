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
#import <AlicloudUtils/AlicloudUtils.h>
#import <AlicloudUtils/AlicloudIPv6Adapter.h>
#import "HttpdnsService_Internal.h"
#import "HttpdnsHostResolver.h"
#import "HttpdnsConfig.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsRequest.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsHostCacheStore.h"
#import "HttpdnsConstants.h"
#import "HttpdnsIPv6Manager.h"
#import "HttpdnsScheduleCenter.h"
#import "UIApplication+ABSHTTPDNSSetting.h"
#import "HttpdnsgetNetworkInfoHelper.h"


NSString *const ALICLOUDHDNS_IPV4 = @"ALICLOUDHDNS_IPV4";
NSString *const ALICLOUDHDNS_IPV6 = @"ALICLOUDHDNS_IPV6";


static NSDictionary *HTTPDNS_EXT_INFO = nil;
static dispatch_queue_t _authTimeOffsetSyncDispatchQueue = 0;

@interface HttpDnsService ()

@property (nonatomic, assign) int accountID;
@property (nonatomic, copy) NSString *secretKey;

/**
 * 每次访问的签名有效期，SDK内部定死，当前不暴露设置接口，有效期定为10分钟。
 */
@property (nonatomic, assign) NSUInteger authTimeoutInterval;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *presetSdnsParamsDict;
@end

@implementation HttpDnsService {
}

@synthesize IPRankingDataSource = _IPRankingDataSource;

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _authTimeOffsetSyncDispatchQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.authTimeOffsetSyncDispatchQueue", DISPATCH_QUEUE_SERIAL);

        // 注册 UIApplication+ABSHTTPDNSSetting 中的Swizzle
        if (!HTTPDNS_INTER) {
            [[UIApplication sharedApplication] onBeforeBootingProtection];
        }
    });
}

#pragma mark -
#pragma mark ---------- singleton

static HttpDnsService * _httpDnsClient = nil;

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _httpDnsClient = [[self alloc] init];
    });
    return _httpDnsClient;
}

- (instancetype)autoInit {
    NSString *sdkVersion;//= HTTPDNS_IOS_SDK_VERSION;
    NSNumber *sdkStatus;
    NSString *sdkId = @"httpdns";

    NSString *accountID;
    NSString *secretKey;

    EMASOptions *defaultOptions = [EMASOptions defaultOptions];
    // Get config
    accountID = defaultOptions.httpdnsAccountId;
    secretKey = defaultOptions.httpdnsSecretKey;
    EMASOptionSDKServiceItem *sdkItem = [defaultOptions sdkServiceItemForSdkId:sdkId];
    if (sdkItem) {
        sdkVersion = sdkItem.version;
        sdkStatus = sdkItem.status;
    }
    if ([HttpdnsUtil isNotEmptyString:accountID]) {
        return [self initWithAccountID:[accountID intValue] secretKey:secretKey];
    }
    NSLog(@"Auto init fail, can not get accountId / secretKey, please check the file named: AliyunEmasServices-Info.plist.");
    return nil;
}

- (instancetype)initWithAccountID:(int)accountID {
    return [self initWithAccountID:accountID secretKey:nil];
}

- (instancetype)initWithAccountID:(int)accountID secretKey:(NSString *)secretKey {
    HttpDnsService *instance = [HttpDnsService sharedInstance];

    instance.accountID = accountID;
    instance.secretKey = secretKey;
    NSString *accountIdString = [NSString stringWithFormat:@"%@", @(accountID)];
    [instance configWithAccountId:accountIdString];

    return instance;
}

- (void)configWithAccountId:(NSString *)accountId {
    [_httpDnsClient requestScheduler];
    _httpDnsClient.timeoutInterval = HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL;
    HTTPDNS_EXT_INFO = @{
        EXT_INFO_KEY_VERSION : HTTPDNS_IOS_SDK_VERSION,
    };
    _httpDnsClient.authTimeoutInterval = HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL;

    if (HTTPDNS_INTER) {
        // 设置固定region 为sg
        [self setRegion:@"sg"];
    }
}

#pragma mark -
#pragma mark -------------- public

- (void)setAuthCurrentTime:(NSUInteger)authCurrentTime {
    [self setInternalAuthTimeBaseBySpecifyingCurrentTime:authCurrentTime];
}

- (void)setInternalAuthTimeBaseBySpecifyingCurrentTime:(NSTimeInterval)currentTime {
    dispatch_sync(_authTimeOffsetSyncDispatchQueue, ^{
        NSTimeInterval localTime = [[NSDate date] timeIntervalSince1970];
        _authTimeOffset = currentTime - localTime;
    });
}

- (void)setCachedIPEnabled:(BOOL)enable {
    [self setPersistentCacheIPEnabled:enable];
}

- (void)setPersistentCacheIPEnabled:(BOOL)enable {
    [_requestScheduler setCachedIPEnabled:enable];
}

- (void)setExpiredIPEnabled:(BOOL)enable {
    [self setReuseExpiredIPEnabled:enable];
}

- (void)setReuseExpiredIPEnabled:(BOOL)enable {
    [_requestScheduler setExpiredIPEnabled:enable];
}

- (void)setHTTPSRequestEnabled:(BOOL)enable {
    HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED = enable;
}

- (void)setNetworkingTimeoutInterval:(NSTimeInterval)timeoutInterval {
    self.timeoutInterval = timeoutInterval;
}

- (void)setRegion:(NSString *)region {
    region = [HttpdnsUtil isNotEmptyString:region] ? region : @"";
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    NSString *olgregion = [userDefault objectForKey:ALICLOUD_HTTPDNS_REGION_KEY];
    if (![region isEqualToString:olgregion]) {
        [userDefault setObject:region forKey:ALICLOUD_HTTPDNS_REGION_KEY];
        HttpdnsScheduleCenter *scheduleCenter  = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter forceUpdateIpListAsyncImmediately]; //强制更新服务IP
        [self cleanHostCache:nil]; //清空本地沙盒和内存的IP缓存
    }
    [_requestScheduler _setRegin:region];
}

- (void)setPreResolveHosts:(NSArray *)hosts {
    if (ALICLOUD_HTTPDNS_JUDGE_SERVER_IP_CACHE == NO) {
        HttpdnsScheduleCenter *scheduleCenter  = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter forceUpdateIpListAsync];
        [_requestScheduler addPreResolveHosts:hosts queryType:HttpdnsQueryIPTypeIpv4];
    } else {
        [_requestScheduler addPreResolveHosts:hosts queryType:HttpdnsQueryIPTypeIpv4];
    }
}


- (void)setPreResolveHosts:(NSArray *)hosts queryIPType:(AlicloudHttpDNS_IPType)ipType {
    HttpdnsQueryIPType ipQueryType;
    switch (ipType) {
        case AlicloudHttpDNS_IPTypeV4:
            ipQueryType = HttpdnsQueryIPTypeIpv4;
            break;
        case AlicloudHttpDNS_IPTypeV6:
            ipQueryType = HttpdnsQueryIPTypeIpv6;
            break;
        case AlicloudHttpDNS_IPTypeV64:
            ipQueryType = HttpdnsQueryIPTypeIpv4 | HttpdnsQueryIPTypeIpv6;
            break;
        default:
            ipQueryType = HttpdnsQueryIPTypeIpv4;
            break;
    }

    if (ALICLOUD_HTTPDNS_JUDGE_SERVER_IP_CACHE == NO) {
        HttpdnsScheduleCenter *scheduleCenter  = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter forceUpdateIpListAsync];
        [_requestScheduler addPreResolveHosts:hosts queryType:ipQueryType];
    } else {
        [_requestScheduler addPreResolveHosts:hosts queryType:ipQueryType];
    }
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
    _IPRankingDataSource = IPRankingDatasource;
}

- (void)enableIPv6:(BOOL)enable {
    [self setIPv6Enabled:enable];
}

- (void)setIPv6Enabled:(BOOL)enable {
    [[HttpdnsIPv6Manager sharedInstance] setIPv6ResultEnable:enable];
}

- (void)enableNetworkInfo:(BOOL)enable {
    [self setReadNetworkInfoEnabled:enable];
}

- (void)setReadNetworkInfoEnabled:(BOOL)enable {
    [HttpdnsgetNetworkInfoHelper setNetworkInfoEnable:enable];
}

- (void)enableCustomIPRank:(BOOL)enable {
    // 不再生效，保留接口
    // 是否开启自定义IP排序，由是否设置IPRankingDatasource和IPRankingDatasource中是否能根据host找到对应的IP来决定
}

- (NSString *)getSessionId {
    return [HttpdnsUtil generateSessionID];
}

#pragma mark -
#pragma mark -------------- resolving method start

- (HttpdnsResult *)resolveHostSync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType {
    return [self resolveHostSync:host byIpType:queryIpType withSdnsParams:nil sdnsCacheKey:nil];
}

- (HttpdnsResult *)resolveHostSync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *,NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey {
    if (!host || [self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    HttpdnsQueryIPType clarifiedQueryIpType = [self determineLegitQueryIpType:queryIpType];

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP.");
        return [self constructResultFromIp:host underQueryType:clarifiedQueryIpType];
    }
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        return nil;
    }

    sdnsParams = [self mergeWithPresetSdnsParams:sdnsParams];
    if ([NSThread isMainThread]) {
        return [self resolveHostSyncNonBlocking:host byIpType:clarifiedQueryIpType withSdnsParams:sdnsParams sdnsCacheKey:cacheKey];
    } else {
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host
                                                     isBlockingRequest:YES
                                                           queryIpType:clarifiedQueryIpType
                                                             sdnsParams:sdnsParams
                                                              cacheKey:cacheKey];
        HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
        if (!hostObject) {
            return nil;
        }
        return [self constructResultFromHostObject:hostObject underQueryType:clarifiedQueryIpType];
    }
}

- (HttpdnsResult *)resolveHostSyncNonBlocking:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType {
    return [self resolveHostSyncNonBlocking:host byIpType:queryIpType withSdnsParams:nil sdnsCacheKey:nil];
}

- (HttpdnsResult *)resolveHostSyncNonBlocking:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *,NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey {
    if (!host || [self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    HttpdnsQueryIPType clarifiedQueryIpType = [self determineLegitQueryIpType:queryIpType];

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP.");
        return [self constructResultFromIp:host underQueryType:clarifiedQueryIpType];
    }
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        return nil;
    }

    sdnsParams = [self mergeWithPresetSdnsParams:sdnsParams];
    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host
                                                 isBlockingRequest:NO
                                                       queryIpType:clarifiedQueryIpType
                                                        sdnsParams:sdnsParams
                                                          cacheKey:cacheKey];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (!hostObject) {
        return nil;
    }
    return [self constructResultFromHostObject:hostObject underQueryType:clarifiedQueryIpType];
}

- (void)resolveHostAsync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType completionHandler:(void (^)(HttpdnsResult *))handler {
    [self resolveHostAsync:host byIpType:queryIpType withSdnsParams:nil sdnsCacheKey:nil completionHandler:handler];
}

- (void)resolveHostAsync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *,NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey completionHandler:(void (^)(HttpdnsResult *))handler {
    if (!host || [self _shouldDegradeHTTPDNS:host]) {
        return;
    }

    HttpdnsQueryIPType clarifiedQueryIpType = [self determineLegitQueryIpType:queryIpType];

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP.");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            handler([self constructResultFromIp:host underQueryType:queryIpType]);
        });
    }
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            handler(nil);
        });
    }

    sdnsParams = [self mergeWithPresetSdnsParams:sdnsParams];
    double start = [[NSDate date] timeIntervalSince1970] * 1000;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host
                                                     isBlockingRequest:YES
                                                           queryIpType:clarifiedQueryIpType
                                                            sdnsParams:sdnsParams
                                                              cacheKey:cacheKey];
        HttpdnsHostObject *hostObject = [strongSelf->_requestScheduler resolveHost:request];
        double innerEnd = [[NSDate date] timeIntervalSince1970] * 1000;
        HttpdnsLogDebug("resolveHostAsync inner cost time is: %f", (innerEnd - start));

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (!hostObject) {
                handler(nil);
            } else {
                handler([self constructResultFromHostObject:hostObject underQueryType:clarifiedQueryIpType]);
            }
        });
    });
}

- (HttpdnsQueryIPType)determineLegitQueryIpType:(HttpdnsQueryIPType)specifiedQueryIpType {
    // 自动选择，需要判断当前网络环境来决定
    if (specifiedQueryIpType == HttpdnsQueryIPTypeAuto) {
        // 如果全局没打开ipv6，那auto的情况下只请求ipv4
        if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
            return HttpdnsQueryIPTypeIpv4;
        }

        AlicloudIPv6Adapter *ipv6Adapter = [AlicloudIPv6Adapter getInstance];
        AlicloudIPStackType stackType = [ipv6Adapter currentIpStackType];
        switch (stackType) {
            case kAlicloudIPdual:
                return HttpdnsQueryIPTypeIpv4 | HttpdnsQueryIPTypeIpv6;
            case kAlicloudIPv6only:
                return HttpdnsQueryIPTypeIpv6;
            case kAlicloudIPv4only:
            default:
                return HttpdnsQueryIPTypeIpv4;
        }
    }

    // 否则就按指定类型来解析
    return specifiedQueryIpType;
}

- (HttpdnsResult *)constructResultFromHostObject:(HttpdnsHostObject *)hostObject underQueryType:(HttpdnsQueryIPType)queryType {
    HttpdnsResult *result = [HttpdnsResult new];
    if (!hostObject) {
        return result;
    }

    result.host = [hostObject getHostName];

    // 由于结果可能是从缓存中获得，所以还要根据实际协议栈情况再筛选下结果
    if (queryType & HttpdnsQueryIPTypeIpv4) {
        NSArray *ipv4s = [hostObject getIps];
        if (ipv4s != nil && [ipv4s count] > 0) {
            NSMutableArray *ipv4Array = [NSMutableArray array];
            for (HttpdnsIpObject *ipObject in ipv4s) {
                [ipv4Array addObject:[ipObject getIpString]];
            }
            result.ips = [ipv4Array copy];
        }
    }

    if (queryType & HttpdnsQueryIPTypeIpv6) {
        NSArray *ipv6s = [hostObject getIp6s];
        if (ipv6s != nil && [ipv6s count] > 0) {
            NSMutableArray *ipv6Array = [NSMutableArray array];
            for (HttpdnsIpObject *ipObject in ipv6s) {
                [ipv6Array addObject:[ipObject getIpString]];
            }
            result.ipv6s = [ipv6Array copy];
        }
    }

    return result;
}

- (HttpdnsResult *)constructResultFromIp:(NSString *)ip underQueryType:(HttpdnsQueryIPType)queryType {
    HttpdnsResult *result = [HttpdnsResult new];
    result.host = ip;

    if (queryType & HttpdnsQueryIPTypeIpv4) {
        if ([[AlicloudIPv6Adapter getInstance] isIPv4Address:ip]) {
            result.ips = @[ip];
        }
    }

    if (queryType & HttpdnsQueryIPTypeIpv6) {
        if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:ip]) {
            result.ipv6s = @[ip];
        }
    }

    return result;
}


- (NSString *)getIpByHostAsync:(NSString *)host {
    NSArray *ips = [self getIpsByHostAsync:host];
    if (ips != nil && ips.count > 0) {
        NSString *ip;
        ip = [HttpdnsUtil safeOjectAtIndex:0 array:ips];
        return ip;
    }
    return nil;
}

- (NSString *)getIPv4ForHostAsync:(NSString *)host {
    NSArray *ips = [self getIPv4ListForHostAsync:host];
    if (ips != nil && ips.count > 0) {
        NSString *ip;
        ip = [HttpdnsUtil safeOjectAtIndex:0 array:ips];
        return ip;
    }
    return nil;
}

- (NSArray *)getIpsByHostAsync:(NSString *)host {
    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        return [NSArray arrayWithObjects:host, nil];
    }
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv4];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isNotEmptyArray:ipsObject]) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                [ipsArray addObject:[ipObject getIpString]];
            }
            return ipsArray;
        }
    }
    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;
}

- (NSArray *)getIPv4ListForHostAsync:(NSString *)host {
    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        return [NSArray arrayWithObjects:host, nil];
    }
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv4];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isNotEmptyArray:ipsObject]) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                [ipsArray addObject:[ipObject getIpString]];
            }
            return ipsArray;
        }
    }
    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;
}

- (NSArray *)getIPv4ListForHostSync:(NSString *)host {
    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        return [NSArray arrayWithObjects:host, nil];
    }
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }
    //需要检查是不是在主线程，如果是主线程，保持异步逻辑
    if ([NSThread isMainThread]) {
        //如果是主线程，仍然使用异步的方式，即先查询缓存，如果没有，则发送异步请求
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv4];
        HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
        if (hostObject) {
            NSArray * ipsObject = [hostObject getIps];
            NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
            if ([HttpdnsUtil isNotEmptyArray:ipsObject]) {
                for (HttpdnsIpObject *ipObject in ipsObject) {
                    [ipsArray addObject:[ipObject getIpString]];
                }
                return ipsArray;
            }
        }
        HttpdnsLogDebug("No available IP cached for %@", host);
        return nil;
    } else {
        NSMutableArray *ipsArray = nil;
        double start = [[NSDate date] timeIntervalSince1970] * 1000;
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:YES queryIpType:HttpdnsQueryIPTypeIpv4];
        __block HttpdnsHostObject *hostObject = [self->_requestScheduler resolveHost:request];
        double end = [[NSDate date] timeIntervalSince1970] * 1000;
        HttpdnsLogDebug("###### getIPv4ListForHostSync result: %@, resolve time delta is %f ms", hostObject, (end - start));

        if (hostObject) {
            NSArray * ipsObject = [hostObject getIps];
            ipsArray = [[NSMutableArray alloc] init];
            if ([HttpdnsUtil isNotEmptyArray:ipsObject]) {
                for (HttpdnsIpObject *ipObject in ipsObject) {
                    [ipsArray addObject:[ipObject getIpString]];
                }
            }
        }
        return ipsArray;
    }
}

- (NSString *)getIpByHostAsyncInURLFormat:(NSString *)host {
    NSString *IP = [self getIpByHostAsync:host];
    if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:IP]) {
        return [NSString stringWithFormat:@"[%@]", IP];
    }
    return IP;
}

- (NSString *)getIPv6ByHostAsync:(NSString *)host {
    if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        return nil;
    }
    NSArray *ips = [self getIPv6sByHostAsync:host];
    NSString *ip = nil;
    if (ips != nil && ips.count > 0) {
        ip = [HttpdnsUtil safeOjectAtIndex:0 array:ips];
    }
    return ip;
}

- (NSString *)getIPv6ForHostAsync:(NSString *)host {
    if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        return nil;
    }
    NSArray *ips = [self getIPv6ListForHostAsync:host];
    NSString *ip = nil;
    if (ips != nil && ips.count > 0) {
        ip = [HttpdnsUtil safeOjectAtIndex:0 array:ips];
    }
    return ip;
}

- (NSArray *)getIPv6sByHostAsync:(NSString *)host {
    if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        return nil;
    }

    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        return [NSArray arrayWithObjects:host, nil];
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv6];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (hostObject) {
        NSArray *ip6sObject = [hostObject getIp6s];
        NSMutableArray *ip6sArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isNotEmptyArray:ip6sObject]) {
            for (HttpdnsIpObject *ip6Object in ip6sObject) {
                [ip6sArray addObject:[ip6Object getIpString]];
            }
            return ip6sArray;
        }
    }
    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;
}

- (NSArray *)getIPv6ListForHostAsync:(NSString *)host {
    if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        return nil;
    }

    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        return [NSArray arrayWithObjects:host, nil];
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv6];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (hostObject) {
        NSArray *ip6sObject = [hostObject getIp6s];
        NSMutableArray *ip6sArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isNotEmptyArray:ip6sObject]) {
            for (HttpdnsIpObject *ip6Object in ip6sObject) {
                [ip6sArray addObject:[ip6Object getIpString]];
            }
            return ip6sArray;
        }
    }
    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;
}

- (NSArray *)getIPv6ListForHostSync:(NSString *)host {
    if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        return nil;
    }

    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        return [NSArray arrayWithObjects:host, nil];
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    if ([NSThread isMainThread]) {
        // 如果是主线程，仍然使用异步的方式，即先查询缓存，如果没有，则发送异步请求
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv6];
        HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
        if (hostObject) {
            NSArray *ipv6List = [hostObject getIp6s];
            NSMutableArray *ipv6Array = [[NSMutableArray alloc] init];
            if ([HttpdnsUtil isNotEmptyArray:ipv6List]) {
                for (HttpdnsIpObject *ipv6Obj in ipv6List) {
                    [ipv6Array addObject:[ipv6Obj getIpString]];
                }
                return ipv6Array;
            }
        }
        HttpdnsLogDebug("No available IP cached for %@", host);
        return nil;
    } else {
        NSMutableArray *ipv6Array = nil;
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:YES queryIpType:HttpdnsQueryIPTypeIpv6];
        HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];

        if (hostObject) {
            NSArray * ipv6List = [hostObject getIp6s];
            ipv6Array = [[NSMutableArray alloc] init];
            if ([HttpdnsUtil isNotEmptyArray:ipv6List]) {
                for (HttpdnsIpObject *ipv6Obj in ipv6List) {
                    [ipv6Array addObject:[ipv6Obj getIpString]];
                }
            }
        }
        return ipv6Array;
    }
}

- (NSDictionary<NSString *,NSArray *> *)getIPv4_v6ByHostAsync:(NSString *)host {
    if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        return nil;
    }

    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        if ([[AlicloudIPv6Adapter getInstance] isIPv4Address:host]) {
            return @{ALICLOUDHDNS_IPV4: @[host?:@""]};
        } else if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:host]) {
            return @{ALICLOUDHDNS_IPV6: @[host?:@""]};
        }
        return nil;
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (hostObject) {
        NSArray *ip4s = [hostObject getIPStrings];
        NSArray *ip6s = [hostObject getIP6Strings];
        NSMutableDictionary *resultMDic = [NSMutableDictionary dictionary];
        if ([HttpdnsUtil isNotEmptyArray:ip4s]) {
            [resultMDic setObject:ip4s forKey:ALICLOUDHDNS_IPV4];
        }
        if ([HttpdnsUtil isNotEmptyArray:ip6s]) {
            [resultMDic setObject:ip6s forKey:ALICLOUDHDNS_IPV6];
        }
        NSLog(@"getIPv4_v6ByHostAsync result is %@", resultMDic);
        return resultMDic;
    }

    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;

}

- (NSDictionary <NSString *, NSArray *>*)getHttpDnsResultHostAsync:(NSString *)host {
    if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        return nil;
    }

    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        if ([[AlicloudIPv6Adapter getInstance] isIPv4Address:host]) {
            return @{ALICLOUDHDNS_IPV4: @[host?:@""]};
        } else if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:host]) {
            return @{ALICLOUDHDNS_IPV6: @[host?:@""]};
        }
        return nil;
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (hostObject) {
        NSArray *ip4s = [hostObject getIPStrings];
        NSArray *ip6s = [hostObject getIP6Strings];
        NSMutableDictionary *httpdnsResult = [NSMutableDictionary dictionary];
        NSLog(@"getHttpDnsResultHostAsync result is %@", httpdnsResult);
        if ([HttpdnsUtil isNotEmptyArray:ip4s]) {
            [httpdnsResult setObject:ip4s forKey:ALICLOUDHDNS_IPV4];
        }
        if ([HttpdnsUtil isNotEmptyArray:ip6s]) {
            [httpdnsResult setObject:ip6s forKey:ALICLOUDHDNS_IPV6];
        }
        return httpdnsResult;
    }

    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;
}

- (NSDictionary <NSString *, NSArray *>*)getHttpDnsResultHostSync:(NSString *)host {
    if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        return nil;
    }

    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        if ([[AlicloudIPv6Adapter getInstance] isIPv4Address:host]) {
            return @{ALICLOUDHDNS_IPV4: @[host?:@""]};
        } else if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:host]) {
            return @{ALICLOUDHDNS_IPV6: @[host?:@""]};
        }
        return nil;
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    if ([NSThread isMainThread]) {
        // 主线程的话仍然是走异步的逻辑
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6];
        HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
        if (hostObject) {
            NSArray *ip4s = [hostObject getIPStrings];
            NSArray *ip6s = [hostObject getIP6Strings];
            NSMutableDictionary *resultMDic = [NSMutableDictionary dictionary];
            NSLog(@"getIPv4_v6ByHostAsync result is %@", resultMDic);
            if ([HttpdnsUtil isNotEmptyArray:ip4s]) {
                [resultMDic setObject:ip4s forKey:ALICLOUDHDNS_IPV4];
            }
            if ([HttpdnsUtil isNotEmptyArray:ip6s]) {
                [resultMDic setObject:ip6s forKey:ALICLOUDHDNS_IPV6];
            }
            return resultMDic;
        }

        HttpdnsLogDebug("No available IP cached for %@", host);
        return nil;
    } else {
        NSMutableDictionary *resultMDic = nil;
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:YES queryIpType:HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6];
        HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
        if (hostObject) {
            NSArray *ip4s = [hostObject getIPStrings];
            NSArray *ip6s = [hostObject getIP6Strings];
            resultMDic = [NSMutableDictionary dictionary];
            if ([HttpdnsUtil isNotEmptyArray:ip4s]) {
                [resultMDic setObject:ip4s forKey:ALICLOUDHDNS_IPV4];
            }
            if ([HttpdnsUtil isNotEmptyArray:ip6s]) {
                [resultMDic setObject:ip6s forKey:ALICLOUDHDNS_IPV6];
            }
            NSLog(@"###### getHttpDnsResultHostSync result is %@", resultMDic);
        }
        return resultMDic;
    }
}

-(NSDictionary <NSString *, NSArray *>*)autoGetIpsByHostAsync:(NSString *)host {
    AlicloudIPv6Adapter *ipv6Adapter = [AlicloudIPv6Adapter getInstance];
    AlicloudIPStackType stackType = [ipv6Adapter currentIpStackType];

    NSMutableDictionary *ipv4_ipv6 = [NSMutableDictionary dictionary];
    if (stackType == kAlicloudIPdual) {
        ipv4_ipv6 = [[self getIPv4_v6ByHostAsync:host] mutableCopy];
    } else if (stackType == kAlicloudIPv4only) {
        NSArray* ipv4Ips = [self getIpsByHostAsync:host];
        if (ipv4Ips != nil) {
            [ipv4_ipv6 setObject:ipv4Ips forKey:ALICLOUDHDNS_IPV4];
        }
    } else if (stackType == kAlicloudIPv6only) {
        NSArray* ipv6Ips = [self getIPv6sByHostAsync:host];
        if (ipv6Ips != nil) {
            [ipv4_ipv6 setObject:ipv6Ips forKey:ALICLOUDHDNS_IPV6];
        }
    }

    return ipv4_ipv6;
}

-(NSDictionary <NSString *, NSArray *>*)autoGetHttpDnsResultForHostAsync:(NSString *)host {
    AlicloudIPv6Adapter *ipv6Adapter = [AlicloudIPv6Adapter getInstance];
    AlicloudIPStackType stackType = [ipv6Adapter currentIpStackType];

    NSMutableDictionary *httpdnsResult = [NSMutableDictionary dictionary];
    if (stackType == kAlicloudIPdual) {
        httpdnsResult = [[self getHttpDnsResultHostAsync:host] mutableCopy];
    } else if (stackType == kAlicloudIPv4only) {
        NSArray* ipv4IpList = [self getIPv4ListForHostAsync:host];
        if (ipv4IpList) {
            [httpdnsResult setObject:ipv4IpList forKey:ALICLOUDHDNS_IPV4];
        }
    } else if (stackType == kAlicloudIPv6only) {
        NSArray* ipv6List = [self getIPv6ListForHostAsync:host];
        if (ipv6List) {
            [httpdnsResult setObject:ipv6List forKey:ALICLOUDHDNS_IPV6];
        }
    }

    return httpdnsResult;
}

- (NSDictionary <NSString *, NSArray *>*)autoGetHttpDnsResultForHostSync:(NSString *)host {
    AlicloudIPv6Adapter *ipv6Adapter = [AlicloudIPv6Adapter getInstance];
    AlicloudIPStackType stackType = [ipv6Adapter currentIpStackType];
    NSMutableDictionary *httpdnsResult = [NSMutableDictionary dictionary];
    if (stackType == kAlicloudIPv4only) {
        NSArray* ipv4IpList = [self getIPv4ListForHostSync:host];
        if (ipv4IpList) {
            [httpdnsResult setObject:ipv4IpList forKey:ALICLOUDHDNS_IPV4];
        }
    } else if (stackType == kAlicloudIPdual) {
        httpdnsResult = [[self getHttpDnsResultHostSync:host] mutableCopy];
    } else if (stackType == kAlicloudIPv6only) {
        NSArray* ipv6List = [self getIPv6ListForHostSync:host];
        if (ipv6List) {
            [httpdnsResult setObject:ipv6List forKey:ALICLOUDHDNS_IPV6];
        }
    }
    return httpdnsResult;
}

- (void)setLogHandler:(id<HttpdnsLoggerProtocol>)logHandler {
    [HttpdnsLog setLogHandler:logHandler];
}

- (void)setTestLogHannder:(id<HttpdnsLog_testOnly_protocol>)handler {
    [HttpdnsLog setTestLogHandler:handler];
}

- (void)cleanHostCache:(NSArray<NSString *> *)hostArray {
    [_requestScheduler cleanCacheWithHostArray:hostArray];
}

- (void)setSdnsGlobalParams:(NSDictionary<NSString *, NSString *> *)params {
    if ([HttpdnsUtil isNotEmptyDictionary:params]) {
        self.presetSdnsParamsDict = params;
    }
}

- (void)clearSdnsGlobalParams {
    self.presetSdnsParamsDict = nil;
}

- (NSDictionary *)getIpsByHostAsync:(NSString *)host withParams:(NSDictionary<NSString *, NSString *> *)params withCacheKey:(NSString *)cacheKey {
    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }
    if (!host) {
        return nil;
    }
    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        return [NSDictionary dictionaryWithObject:host forKey:@"host"];
    }
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    if (![HttpdnsUtil isNotEmptyString: cacheKey]) {
        cacheKey = @"";
    }

    params = [self mergeWithPresetSdnsParams:params];
    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:NO queryIpType:HttpdnsQueryIPTypeIpv4 sdnsParams:params cacheKey:cacheKey];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        NSMutableDictionary * ipsDictionary = [[NSMutableDictionary alloc] init];
        [ipsDictionary setObject:host forKey:@"host"];
        if ([HttpdnsUtil isNotEmptyDictionary:hostObject.extra]) {
            [ipsDictionary setObject:hostObject.extra forKey:@"extra"];
        }
        if ([HttpdnsUtil isNotEmptyArray:ipsObject]) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                [ipsArray addObject:[ipObject getIpString]];
            }
            [ipsDictionary setObject:ipsArray forKey:@"ips"];
            return ipsDictionary;
        }
    }
    return nil;
}


#pragma mark -
#pragma mark -------------- private

- (NSDictionary<NSString *, NSString *> *)mergeWithPresetSdnsParams:(NSDictionary<NSString *, NSString *> *)params {
    if (!self.presetSdnsParamsDict) {
        return params;
    }


    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:self.presetSdnsParamsDict];
    if (params) {
        // 明确传参的params优先级更高，可以覆盖预配置的参数
        [result addEntriesFromDictionary:params];
    }
    return result;
}

- (NSDictionary *)IPRankingDataSource {
    NSDictionary *IPRankingDataSource = nil;
    @synchronized(self) {
        if ([HttpdnsUtil isNotEmptyDictionary:_IPRankingDataSource]) {
            IPRankingDataSource = _IPRankingDataSource;
        }
    }
    return IPRankingDataSource;
}

- (BOOL)_shouldDegradeHTTPDNS:(NSString *)host {
    if (self.delegate && [self.delegate respondsToSelector:@selector(shouldDegradeHTTPDNS:)]) {
        return [self.delegate shouldDegradeHTTPDNS:host];
    }
    return NO;
}

#pragma mark -
#pragma mark -------------- HttpdnsRequestScheduler_Internal

- (NSTimeInterval)authTimeOffset {
    __block NSUInteger authTimeOffset = 0;
    dispatch_sync(_authTimeOffsetSyncDispatchQueue, ^{
        authTimeOffset = _authTimeOffset;
    });
    return authTimeOffset;
}

- (HttpdnsRequestScheduler *)requestScheduler {
    if (_requestScheduler) {
        return _requestScheduler;
    }
    HttpdnsRequestScheduler *requestScheduler = [[HttpdnsRequestScheduler alloc] init];
    _requestScheduler = requestScheduler;
    return _requestScheduler;
}

- (NSString *)getIpByHost:(NSString *)host {
    NSArray *ips = [self getIpsByHost:host];
    if (ips != nil && ips.count > 0) {
        NSString *ip;
        ip = [HttpdnsUtil safeOjectAtIndex:0 array:ips];
        return ip;
    }
    return nil;
}

- (NSArray *)getIpsByHost:(NSString *)host {
    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        return [NSArray arrayWithObjects:host, nil];
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host isBlockingRequest:YES queryIpType:HttpdnsQueryIPTypeIpv4];
    HttpdnsHostObject *hostObject = [_requestScheduler resolveHost:request];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isNotEmptyArray:ipsObject]) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                [HttpdnsUtil safeAddObject:[ipObject getIpString] toArray:ipsArray];
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

@end
