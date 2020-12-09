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
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsRequest.h"
#import "HttpdnsConfig.h"
#import "HttpdnsModel.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsHostCacheStore.h"
#import "HttpDnsHitService.h"
#import "HttpdnsConstants.h"
#import "HttpdnsIPv6Manager.h"
#import "HttpdnsScheduleCenter.h"

static NSDictionary *HTTPDNS_EXT_INFO = nil;
static dispatch_queue_t _authTimeOffsetSyncDispatchQueue = 0;

@interface HttpDnsService ()

@property (nonatomic, assign) int accountID;
@property (nonatomic, copy) NSString *secretKey;

/**
 * 每次访问的签名有效期，SDK内部定死，当前不暴露设置接口，有效期定为10分钟。
 */
@property (nonatomic, assign) NSUInteger authTimeoutInterval;
@property (nonatomic, copy) NSString *globalParams;
@property (nonatomic, copy) NSDictionary *globalParamsDic;
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
    if ([EMASTools isValidString:accountID]) {
        return [self initWithAccountID:[accountID intValue] secretKey:secretKey];
    }
    NSLog(@"Auto init fail, can not get accountId / secretKey, please check the file named: AliyunEmasServices-Info.plist.");
    return nil;
}

- (instancetype)initWithAccountID:(int)accountID {
    return [self initWithAccountID:accountID secretKey:nil];
}

// 鉴权控制台：httpdns.console.aliyun.com
- (instancetype)initWithAccountID:(int)accountID secretKey:(NSString *)secretKey {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _httpDnsClient = [super init];
        _httpDnsClient.accountID = accountID;
        if ([HttpdnsUtil isValidString:secretKey]) {
            _httpDnsClient.secretKey = [secretKey copy];
        }
    });
    return _httpDnsClient;
}

- (void)setAuthCurrentTime:(NSUInteger)authCurrentTime {
    if (![self checkServiceStatus]) {
        return;
    }
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
    NSDictionary *extras = @{
                             ALICLOUD_HTTPDNS_BEACON_REQUEST_PARAM_ACCOUNTID : accountId
                             };
    EMASBeaconService *beaconService =  [[EMASBeaconService alloc] initWithAppKey:HTTPDNS_BEACON_APPKEY
                                                                        appSecret:HTTPDNS_BEACON_APPSECRECT
                                                                       SDKVersion:HTTPDNS_IOS_SDK_VERSION
                                                                            SDKID:@"httpdns"
                                                                        extension:extras];
    [beaconService enableLog:YES];
    [beaconService getBeaconConfigStringByKey:@"___httpdns_service___" completionHandler:^(NSString *result, NSError *error) {
        if ([HttpdnsUtil isValidString:result]) {
            HttpdnsLogDebug("beacon result: %@", result);
            id jsonObj = [HttpdnsUtil convertJsonStringToObject:result];
            if ([HttpdnsUtil isValidDictionary:jsonObj]) {
                NSDictionary *serviceStatus = jsonObj;
                /**
                 beacon result format:
                 {
                    "status": "xx"
                    "ut": "xx"
                    "ip-ranking": "xx"
                 }
                 **/
                NSString *sdkStatus = [serviceStatus objectForKey:ALICLOUD_HTTPDNS_BEACON_STATUS_KEY];
                if ([sdkStatus isEqualToString:ALICLOUD_HTTPDNS_BEACON_SDK_DISABLE]) {
                    // sdk disable
                    [[HttpdnsScheduleCenter sharedInstance] setSDKDisableFromBeacon];
                } else {
                    [[HttpdnsScheduleCenter sharedInstance] clearSDKDisableFromBeacon];
                }
                
                /* 检查打点开关 */
                NSString *utStatus = [serviceStatus objectForKey:@"ut"];
                if ([HttpdnsUtil isValidString:utStatus] && [utStatus isEqualToString:@"disabled"]) {
                    HttpdnsLogDebug("Beacon [___httpdns_service___] - [ut] is disabled, disable hit service.");
                    [HttpDnsHitService disableHitService];
                }
                
                NSString *ipRankingStatus = [serviceStatus objectForKey:@"ip-ranking"];
                if ([HttpdnsUtil isValidString:ipRankingStatus] && [ipRankingStatus isEqualToString:@"enable"]) {
                    self.requestScheduler.IPRankingEnabled = YES;
                } else {
                    HttpdnsLogDebug("Beacon [___httpdns_service___] - [ip-ranking] is disabled, disable ip-ranking feature.");
                    self.requestScheduler.IPRankingEnabled = NO;
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
    if (![self checkServiceStatus]) {
        return;
    }
    if (ALICLOUD_HTTPDNS_JUDGE_SERVER_IP_CACHE == NO) {
        HttpdnsScheduleCenter *scheduleCenter  = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter forceUpdateIpListAsync];
        [_requestScheduler addPreResolveHosts:hosts];
    } else {
        [_requestScheduler addPreResolveHosts:hosts];
    }
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
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host synchronously:YES queryType:HttpdnsIPTypeIpv4];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isValidArray:ipsObject]) {
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

- (NSString *)getIpByHostAsync:(NSString *)host {
    if (![self checkServiceStatus]) {
        return nil;
    }
    NSArray *ips = [self getIpsByHostAsync:host];
    if (ips != nil && ips.count > 0) {
        NSString *ip;
        ip = [HttpdnsUtil safeOjectAtIndex:0 array:ips];
        return ip;
    }
    return nil;
}

- (NSArray *)getIpsByHostAsync:(NSString *)host {
    if (![self checkServiceStatus]) {
        return nil;
    }
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
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host synchronously:NO queryType:HttpdnsIPTypeIpv4];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isValidArray:ipsObject]) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                [ipsArray addObject:[ipObject getIpString]];
            }
            [self bizPerfUserGetIPWithHost:host success:YES];
            return ipsArray;
        }
    }
    [self bizPerfUserGetIPWithHost:host success:NO];
    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;
}

- (void)bizPerfUserGetIPWithHost:(NSString *)host
                         success:(BOOL)success {
    BOOL cachedIPEnabled = [self.requestScheduler _getCachedIPEnabled];
    [HttpDnsHitService bizPerfUserGetIPWithHost:host success:YES cacheOpen:cachedIPEnabled];
}

- (NSString *)getIpByHostAsyncInURLFormat:(NSString *)host {
    if (![self checkServiceStatus]) {
        return nil;
    }
    NSString *IP = [self getIpByHostAsync:host];
    if ([[AlicloudIPv6Adapter getInstance] isIPv6Address:IP]) {
        return [NSString stringWithFormat:@"[%@]", IP];
    }
    return IP;
}

- (void)setHTTPSRequestEnabled:(BOOL)enable {
    if (![self checkServiceStatus]) {
        return;
    }
    HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED = enable;
}

- (void)setCachedIPEnabled:(BOOL)enable {
    if (![self checkServiceStatus]) {
        return;
    }
    [_requestScheduler setCachedIPEnabled:enable];
    [HttpDnsHitService bizCacheEnable:enable];
}

- (void)setExpiredIPEnabled:(BOOL)enable {
    if (![self checkServiceStatus]) {
        return;
    }
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
    if (![self checkServiceStatus]) {
        return;
    }
    [_requestScheduler setPreResolveAfterNetworkChanged:enable];
}

- (void)setIPRankingDatasource:(NSDictionary<NSString *, NSNumber *> *)IPRankingDatasource {
    if (![self checkServiceStatus]) {
        return;
    }
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

- (void)setLogHandler:(id<HttpdnsLoggerProtocol>)logHandler {
    [HttpdnsLog setLogHandler:logHandler];
}

- (void)setRegion:(NSString *)region {
    
    if (![self checkServiceStatus]) {
        return;
    }
    
    if ([HttpdnsUtil isValidString:region]) {
        NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
        NSString *olgregion = [userDefault objectForKey:@"HttpdnsRegion"];
        if (![region isEqualToString:olgregion]) {
            [userDefault setObject:region forKey:@"HttpdnsRegion"];
            HttpdnsScheduleCenter *scheduleCenter  = [HttpdnsScheduleCenter sharedInstance];
            [scheduleCenter forceUpdateIpListAsync];
        }
    }
}

- (NSString *)getSessionId {
    return [HttpdnsUtil generateSessionID];
}

- (void)enableIPv6:(BOOL)enable {
    [[HttpdnsIPv6Manager sharedInstance] setIPv6ResultEnable:enable];
}

- (NSString *)getIPv6ByHostAsync:(NSString *)host {
    
    if (![self checkServiceStatus]) {
        return nil;
    }
    
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

- (NSArray *)getIPv6sByHostAsync:(NSString *)host {
    
    if (![self checkServiceStatus]) {
        return nil;
    }
    
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
    
    HttpdnsHostObject *hostObject = [_requestScheduler addSingleHostAndLookup:host synchronously:NO queryType:HttpdnsIPTypeIpv6];
    if (hostObject) {
        NSArray *ip6sObject = [hostObject getIp6s];
        NSMutableArray *ip6sArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isValidArray:ip6sObject]) {
            for (HttpdnsIpObject *ip6Object in ip6sObject) {
                [ip6sArray addObject:[ip6Object getIpString]];
            }
            [self bizPerfUserGetIPWithHost:host success:YES];
            return ip6sArray;
        }
    }
    [self bizPerfUserGetIPWithHost:host success:NO];
    HttpdnsLogDebug("No available IP cached for %@", host);
    return nil;
}

- (BOOL)checkServiceStatus {
    if ([HttpdnsScheduleCenter sharedInstance].stopService) {
        HttpdnsLogDebug("HttpDns service disable, return.");
        return NO;
    }
    return YES;
}

- (void)setSdnsGlobalParams:(NSDictionary<NSString *, NSString *> *)params {
    if ([HttpdnsUtil isValidDictionary:params]) {
        _globalParams = [self limitPapams:params];
        self.globalParamsDic = params;
    } else {
        _globalParams = @"";
    }
}

- (void)clearSdnsGlobalParams {
    _globalParams = nil;
}

- (NSString *)limitPapams:(NSDictionary<NSString *, NSString *> *)params {
    NSString *str = @"^[A-Za-z0-9\-_]+";
    NSPredicate *emailTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", str];
    NSMutableArray *arr = [[NSMutableArray alloc] initWithCapacity:0];
    
    [params enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        if (![emailTest evaluateWithObject:key]) {
            HttpdnsLogDebug("\n ====== 此参数 key: %@ 不符合要求 , 参数名 key 中不允许出现特殊字符", key);
            return ;
        } else {
            NSString *str = [NSString stringWithFormat:@"%@%@",key, obj];
            if ([str lengthOfBytesUsingEncoding:NSUnicodeStringEncoding] > 1000 ) {
                HttpdnsLogDebug("\n ====== 参数名和参数值的整体大小不应超过 1000 字节");
                return ;
            } else {
                NSString *str = [NSString stringWithFormat:@"&sdns-%@=%@", key,obj];
                [arr addObject:str];
            }
        }
    }];

    HttpdnsLogDebug("\n ====== 入参: %@",[arr componentsJoinedByString:@""]);
    return [arr componentsJoinedByString:@""];
}

- (NSDictionary *)getIpsByHostAsync:(NSString *)host withParams:(NSDictionary<NSString *, NSString *> *)params withCacheKey:(NSString *)cacheKey {
    
    if (![self checkServiceStatus]) {
        return nil;
    }
    
    if ([self.delegate shouldDegradeHTTPDNS:host]) {
        return nil;
    }
    if (!host) {
        return nil;
    }
    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP.");
        return [NSDictionary dictionaryWithObject:host forKey:@"host"];
    }
    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal.");
        return nil;
    }
    
    NSString *partsParams;
    if ([HttpdnsUtil isValidDictionary:params]) {
        partsParams = [self limitPapams:params];
    } else {
        partsParams = @"";
    }
    
    if (![HttpdnsUtil isValidString: cacheKey]) {
        cacheKey = @"";
    }
    HttpdnsHostObject *hostObject;
    NSString * allParams;
    NSString *hostkey = [NSString stringWithFormat:@"%@%@",host,cacheKey];
    if (![HttpdnsUtil isValidString:_globalParams]) {
        if (![HttpdnsUtil isValidString:partsParams]) {
            allParams = host;
        } else {
            allParams = [NSString stringWithFormat:@"%@]%@]%@",host,partsParams,hostkey];
        }
    } else {
        if ([HttpdnsUtil isValidString:partsParams]) {
            NSMutableDictionary *allParamDic = [NSMutableDictionary dictionary];
            [self.globalParamsDic enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                [allParamDic setObject:obj forKey:key];
            }];
            [params enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                [allParamDic setObject:obj forKey:key];
            }];
            partsParams = [self limitPapams:allParamDic];
            allParams = [NSString stringWithFormat:@"%@]%@]%@",host,partsParams,hostkey];
        } else {
            allParams = [NSString stringWithFormat:@"%@]%@]%@",host,_globalParams,hostkey];
        }
    }
    hostObject = [_requestScheduler addSingleHostAndLookup:allParams synchronously:NO queryType:HttpdnsIPTypeIpv4];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getIps];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        NSMutableDictionary * ipsDictionary = [[NSMutableDictionary alloc] init];
        [ipsDictionary setObject:host forKey:@"host"];
        if ([HttpdnsUtil isValidDictionary:hostObject.extra]) {
            [ipsDictionary setObject:hostObject.extra forKey:@"extra"];
        }
        if ([HttpdnsUtil isValidArray:ipsObject]) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                [ipsArray addObject:[ipObject getIpString]];
            }
            [ipsDictionary setObject:ipsArray forKey:@"ips"];
            [self bizPerfUserGetIPWithHost:hostkey success:YES];
            return  ipsDictionary;
        }
    }
    [self bizPerfUserGetIPWithHost:hostkey success:NO];
    return nil;
}

@end
