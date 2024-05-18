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

#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsModel.h"
#import "HttpdnsRequest.h"
#import "HttpdnsConfig.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsConstants.h"
#import "HttpdnsHostCacheStore.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsIPRecord.h"
#import "HttpdnsUtil.h"
#import "HttpdnsTCPSpeedTester.h"
#import "HttpdnsgetNetworkInfoHelper.h"
#import "HttpdnsIPv6Manager.h"
#import "HttpDnsLocker.h"

static NSString *const ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_KEY_STATUS = @"disable_status_key";
static NSString *const ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_FILE_NAME = @"disable_status";

bool ALICLOUD_HTTPDNS_JUDGE_SERVER_IP_CACHE = NO;


NSString * ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED = ALICLOUD_HTTPDNS_SERVER_IP_DEFAULT;
NSString * ALICLOUD_HTTPDNS_SERVER_IPV6_ACTIVATED = ALICLOUD_HTTPDNS_SERVER_IPV6_DEFAULT;


NSString *const ALICLOUD_HTTPDNS_VALID_SERVER_CERTIFICATE_IP = @"203.107.1.1";

NSString *const ALICLOUD_HTTPDNS_HTTP_SERVER_PORT = @"80";
NSString *const ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT = @"443";

// 历史原因，如果region没设置，默认为空字符串
NSString *const ALICLOUD_DEFAULT_REGION = @"";

//服务ip list
NSArray *ALICLOUD_HTTPDNS_SERVER_IP_LIST = nil;

//服务ipv6 list
NSArray *ALICLOUD_HTTPDNS_SERVER_IPV6_LIST = nil;

NSString *ALICLOUD_HTTPDNS_SERVER_IP_REGION = @""; //当前服务IP的region，默认为空为国内场景

NSTimeInterval ALICLOUD_HTTPDNS_SERVER_DISABLE_STATUS_CACHE_TIMEOUT_INTERVAL = 0;

static dispatch_queue_t _hostCacheQueue = NULL;
static dispatch_queue_t _asyncResolveHostQueue = NULL;
static dispatch_queue_t _syncLoadCacheQueue = NULL;

@interface HttpdnsRequestScheduler()

/**
 * disable 状态置位的逻辑会在 `-mergeLookupResultToManager:forHost:` 中执行。
 */
@property (nonatomic, assign, getter=isServerDisable) BOOL serverDisable;
@property (nonatomic, strong) NSDate *lastServerDisableDate;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, copy) NSString *disableStatusPath;
@property (nonatomic, assign) BOOL cachedIPEnabled;
@property (nonatomic, copy) NSString *customRegion; //当前设置的region

@end

@implementation HttpdnsRequestScheduler {
    long _lastNetworkStatus;
    BOOL _isExpiredIPEnabled;
    BOOL _isPreResolveAfterNetworkChangedEnabled;
    NSMutableDictionary *_hostManagerDict;
    dispatch_queue_t _syncDispatchQueue;
    NSLock *_lock;
}

+ (void)initialize {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        _hostCacheQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.hostCacheQueue", DISPATCH_QUEUE_SERIAL);
        _syncLoadCacheQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.syncLoadCacheQueue", DISPATCH_QUEUE_SERIAL);
        _asyncResolveHostQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.asyncResolveHostQueue", DISPATCH_QUEUE_CONCURRENT);
    });

    [self configureServerIPsAndResetActivatedIPTime];
}

- (instancetype)init {
    if (self = [super init]) {
        _lastNetworkStatus = [AlicloudReachabilityManager shareInstance].currentNetworkStatus;
        _isExpiredIPEnabled = NO;
        _IPRankingEnabled = NO;
        _customIPRankingEnabled = YES;
        _isPreResolveAfterNetworkChangedEnabled = NO;
        _customRegion = [[NSUserDefaults standardUserDefaults] objectForKey:ALICLOUD_HTTPDNS_REGION_KEY];
        if (!_customRegion) {
            _customRegion = ALICLOUD_DEFAULT_REGION;
        }
        _syncDispatchQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.sync", DISPATCH_QUEUE_SERIAL);
        _hostManagerDict = [[NSMutableDictionary alloc] init];
        _lock = [[NSLock alloc] init];
        [AlicloudIPv6Adapter getInstance];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(networkChanged:)
                                                     name:ALICLOUD_NETWOEK_STATUS_NOTIFY
                                                   object:nil];
        [self initServerDisableStatus];
        _testHelper = [[HttpdnsRequestTestHelper alloc] init];
    }
    return self;
}

+ (void)configureServerIPsAndResetActivatedIPTime {
    ALICLOUD_HTTPDNS_SERVER_IP_LIST = @[ALICLOUD_HTTPDNS_SERVER_IP_DEFAULT];  //默认的内置服务ipv4 地址 根据国际站来区分
    ALICLOUD_HTTPDNS_SERVER_IPV6_LIST = @[ALICLOUD_HTTPDNS_SERVER_IPV6_DEFAULT];  //默认的内置服务ipv6 地址 根据国际站来区分
    ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 30; // 30 second
    ALICLOUD_HTTPDNS_SERVER_DISABLE_STATUS_CACHE_TIMEOUT_INTERVAL = 1 * 24 * 60 * 60; // one day
}

- (void)initServerDisableStatus {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.cacheQueue, ^{
        NSDictionary *json = [HttpdnsPersistenceUtils getJSONFromDirectory:[HttpdnsPersistenceUtils disableStatusPath]
                                                                  fileName:ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_FILE_NAME
                                                                   timeout:ALICLOUD_HTTPDNS_SERVER_DISABLE_STATUS_CACHE_TIMEOUT_INTERVAL];
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!json) {
            //本地无缓存，常见于第一次安装，或者未发生过 DNS 故障。
            return;
        }

       strongSelf.serverDisable = [[HttpdnsUtil safeObjectForKey:ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_KEY_STATUS dict:json] boolValue];
        if (strongSelf.serverDisable) {
            HttpdnsLogDebug("HTTPDNS is disabled");
        }
    });
}

- (void)addPreResolveHosts:(NSArray *)hosts queryType:(HttpdnsQueryIPType)queryType{
    if (![HttpdnsUtil isValidArray:hosts]) {
        return;
    }
    dispatch_async(_syncDispatchQueue, ^{
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        for (NSString *hostName in hosts) {
            if ([self isHostsNumberLimitReached]) {
                break;
            }
            HttpdnsHostObject *hostObject = [self hostObjectFromCacheForHostName:hostName];
            if (!hostObject 
                || [hostObject isExpiredUnderQueryIpType:queryType]
                || [hostObject isRegionNotMatch:self.customRegion underQueryIpType:queryType]) {

                [self resolveHost:hostName synchronously:NO queryType:queryType];
                HttpdnsLogDebug("Pre resolve host by async lookup, host: %@", hostName);
            }
        }
    });
}

#pragma mark - core method for all public query API
- (HttpdnsHostObject *)resolveHost:(NSString *)host synchronously:(BOOL)sync queryType:(HttpdnsQueryIPType)queryType {
    HttpdnsLogDebug("resolveHost, host: %@, queryType: %ld", host, queryType);
    NSString *originalHost = host;
    NSArray *hostArray= [host componentsSeparatedByString:@"]"];
    NSString *cacheKey = [hostArray lastObject];

    if (![HttpdnsUtil isValidString:cacheKey]) {
        return nil;
    }

    BOOL needToQuery = NO;
    BOOL needToWaitForResult = NO;

    HttpDnsLocker *lockerManager = [HttpDnsLocker sharedInstance];
    [lockerManager lock:cacheKey queryType:queryType];

    HttpdnsHostObject *result = [self hostObjectFromCacheForHostName:cacheKey];
    HttpdnsLogDebug("try to load from cache, cacheKey: %@, result: %@", cacheKey, result);

    if (!result) {
        if ([self isHostsNumberLimitReached]) {
            return nil;
        }
        needToQuery = YES;
        needToWaitForResult = YES;
        result = [HttpdnsHostObject new];
        result.ips = @[];
        result.ip6s = @[];
        result.hostName = cacheKey;
        result.extra = @{};
        [HttpdnsUtil safeAddValue:result key:cacheKey toDict:_hostManagerDict];
    } else {
        do {
            if ([result isIpEmptyUnderQueryIpType:queryType]) {
                needToQuery = YES;
                break;
            }

            if ([result isRegionNotMatch:[self customRegion] underQueryIpType:queryType]) {
                needToQuery = YES;
                break;
            }

            if ([result isExpiredUnderQueryIpType:queryType]) {
                if (_isExpiredIPEnabled || [result isLoadFromDB]) {
                    needToQuery = YES;
                    needToWaitForResult = NO;
                    HttpdnsLogDebug("The ips is expired, but we accept it, host: %@', queryType: %ld", host, queryType);
                    break;
                } else {
                    needToQuery = YES;
                    needToWaitForResult = YES;
                    break;
                }
            }
        } while (NO);
    }

    if (!needToQuery) {
        [lockerManager unlock:cacheKey queryType:queryType];
        return result;
    }

    if (sync && needToWaitForResult) {
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        result = [self executeRequest:originalHost retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex error:nil queryIPType:queryType];
        [lockerManager unlock:cacheKey queryType:queryType];
        return result;
    } else {
        dispatch_async(_asyncResolveHostQueue, ^{
            HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
            [self executeRequest:originalHost retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex error:nil queryIPType:queryType];
            [lockerManager unlock:cacheKey queryType:queryType];
        });
        return result;
    }
}

/// 判断当前hostObject 是否需要开启查询
- (BOOL)needToQueryWithCachedHostObject:(HttpdnsHostObject *)hostObject underQueryIpType:(HttpdnsQueryIPType)queryType {
    return NO;
}

- (void)mergeLookupResultToManager:(HttpdnsHostObject *)result forHost:(NSString *)host {
    NSString * originalHost = host;
    NSArray *hostArray= [host componentsSeparatedByString:@"]"];
    host = [hostArray lastObject];

    if (!result) {
        return;
    }

    [self setServerDisable:NO host:host];
    HttpdnsHostObject *cachedHostObject = [HttpdnsUtil safeObjectForKey:host dict:_hostManagerDict];
    int64_t TTL = [result getTTL];
    int64_t lastLookupTime = [result getLastLookupTime];
    NSArray<NSString *> *IPStrings = [result getIPStrings];
    NSArray<NSString *> *IP6Strings = [result getIP6Strings];
    NSArray<HttpdnsIpObject *> *IPObjects = [result getIps];
    NSArray<HttpdnsIpObject *> *IP6Objects = [result getIp6s];
    NSDictionary* Extra  = [result getExtra];
    NSString *ipRegion = result.ipRegion;
    NSString *ip6Region = result.ip6Region;

    //拿到当前域名查询策略
    HttpdnsQueryIPType queryIPType = [[HttpdnsIPv6Manager sharedInstance] getQueryHostIPType:host];

    //删除已经完成查询的域名的查询策略
    [[HttpdnsIPv6Manager sharedInstance] removeQueryHost:host];

    if (cachedHostObject) {
        [cachedHostObject setTTL:TTL];
        [cachedHostObject setLastLookupTime:lastLookupTime];
        [cachedHostObject setIsLoadFromDB:NO];

        if (queryIPType & HttpdnsQueryIPTypeIpv4) {
            [cachedHostObject setIps:IPObjects];
            [cachedHostObject setV4TTL:result.getV4TTL];
            [cachedHostObject setLastIPv4LookupTime:result.lastIPv4LookupTime];
            cachedHostObject.ipRegion = ipRegion;
        }

        if (queryIPType & HttpdnsQueryIPTypeIpv6) {
            [cachedHostObject setIp6s:IP6Objects];
            [cachedHostObject setV6TTL:result.getV6TTL];
            [cachedHostObject setLastIPv6LookupTime:result.lastIPv6LookupTime];
            cachedHostObject.ip6Region = ip6Region;
        }

        if ([HttpdnsUtil isValidDictionary:result.extra]) {
            [cachedHostObject setExtra:Extra];
        }

        HttpdnsLogDebug("####### Update %@: %@", host, result);
    } else {
        HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
        [hostObject setHostName:host];
        [hostObject setLastLookupTime:lastLookupTime];
        [hostObject setTTL:TTL];

        [hostObject setIps:IPObjects];
        [hostObject setV4TTL:result.getV4TTL];
        [hostObject setLastIPv4LookupTime:result.lastIPv4LookupTime];
        hostObject.ipRegion = ipRegion;

        [hostObject setIp6s:IP6Objects];
        [hostObject setV6TTL:result.getV6TTL];
        [hostObject setLastIPv6LookupTime:result.lastIPv6LookupTime];
        hostObject.ip6Region = ip6Region;


        if ([HttpdnsUtil isValidDictionary:result.extra]) {
            [hostObject setExtra:Extra];
        }

        HttpdnsLogDebug("###### New resolved item: %@: %@", host, result);
        [HttpdnsUtil safeAddValue:hostObject key:host toDict:_hostManagerDict];
    }

    if([HttpdnsUtil isValidDictionary:result.extra]) {
        [self sdnsCacheHostRecordAsyncIfNeededWithHost:host IPs:IPStrings IP6s:IP6Strings TTL:TTL withExtra:Extra ipRegion:ipRegion ip6Region:ip6Region];
    } else {
        [self cacheHostRecordAsyncIfNeededWithHost:host IPs:IPStrings IP6s:IP6Strings TTL:TTL ipRegion:ipRegion ip6Region:ip6Region];
    }

    [self aysncUpdateIPRankingWithResult:result forHost:originalHost];
}

- (void)aysncUpdateIPRankingWithResult:(HttpdnsHostObject *)result forHost:(NSString *)host {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        [self syncUpdateIPRankingWithResult:result forHost:host];
    });
}

- (void)syncUpdateIPRankingWithResult:(HttpdnsHostObject *)result forHost:(NSString *)host {
    if (!self.IPRankingEnabled && !self.customIPRankingEnabled) {
        return;
    }
    NSArray *hostArray= [host componentsSeparatedByString:@"]"];
    host = [hostArray lastObject];
    NSArray<NSString *> *IPStrings = [result getIPStrings];
    NSArray *sortedIps = [[HttpdnsTCPSpeedTester new] ipRankingWithIPs:IPStrings host:host];
    [self updateHostManagerDictWithIPs:sortedIps host:host];
}

- (void)updateHostManagerDictWithIPs:(NSArray *)IPs host:(NSString *)host {
    if (!self.IPRankingEnabled && !self.customIPRankingEnabled) {
        return;
    }
    HttpdnsHostObject *hostObject = [HttpdnsUtil safeObjectForKey:host dict:_hostManagerDict];
    if (!hostObject) {
        return;
    }
    if (![HttpdnsUtil isValidArray:IPs] || ![HttpdnsUtil isValidString:host]) {
        return;
    }
    @synchronized(self) {
        //FIXME:
        NSMutableArray *ipArray = [[NSMutableArray alloc] init];
        for (NSString *ip in IPs) {
            if (![HttpdnsUtil isValidString:ip]) {
                continue;
            }
            HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
            // Adapt to IPv6-only network.
            if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
                [ipObject setIp:[[AlicloudIPv6Adapter getInstance] handleIpv4Address:ip]];
            } else {
                [ipObject setIp:ip];
            }
            [ipArray addObject:ipObject];
        }
        [hostObject setIps:ipArray];
        [HttpdnsUtil safeAddValue:hostObject key:host toDict:_hostManagerDict];
    }
}

/*!
 * 用户访问引发的嗅探超时的情况，和重试引起的主动嗅探都会访问该方法，但是主动嗅探场景会在 `-[setServerDisable:]` 里直接返回。
 *
 if (_serverDisable == serverDisable) { return; }
 */
- (void)canNotResolveHost:(NSString *)host error:(NSError *)error isRetry:(BOOL)isRetry activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    NSDictionary *userInfo = error.userInfo;
    //403 ServiceLevelDeny 错误强制更新，不触发disable机制。
    BOOL isServiceLevelDeny = false;
    NSString *errorMessage = [HttpdnsUtil safeObjectForKey:ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY dict:userInfo];
    if ([HttpdnsUtil isValidString:errorMessage]) {
        isServiceLevelDeny = [errorMessage isEqualToString:ALICLOUD_HTTPDNS_ERROR_SERVICE_LEVEL_DENY];
    }

    if (isServiceLevelDeny) {
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter forceUpdateIpListAsync];
        return;
    }

    BOOL isTimeoutError = [self isTimeoutError:error isHTTPS:HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED];
    NSString * CopyHost = host;
    NSArray *hostArray= [host componentsSeparatedByString:@"]"];
    host = [hostArray lastObject];

    if (isRetry && isTimeoutError) {
        [self setServerDisable:YES host:CopyHost activatedServerIPIndex:activatedServerIPIndex];
    }
    [self mergeLookupResultToManager:nil forHost:CopyHost];
}

- (HttpdnsHostObject *)executeRequest:(NSString *)host
                           retryCount:(int)hasRetryedCount
               activatedServerIPIndex:(NSInteger)activatedServerIPIndex
                                error:(NSError *)error
                          queryIPType:(HttpdnsQueryIPType)queryIPType {
    NSString * originalHost = host;
    NSArray *hostArray= [host componentsSeparatedByString:@"]"];
    NSString *cacheKey = [hostArray lastObject];

    if (hasRetryedCount > HTTPDNS_MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogDebug("Internal request retry count exceed limit, host: %@", host);
        [self canNotResolveHost:originalHost error:error isRetry:YES activatedServerIPIndex:activatedServerIPIndex];
        return nil;
    }

    if ([self isDisableToServer]) {
        return nil;
    }

    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    NSInteger newActivatedServerIPIndex = [scheduleCenter nextServerIPIndexFromIPIndex:activatedServerIPIndex increase:hasRetryedCount];

    HttpdnsLogDebug("Internal request for %@ starts.", cacheKey);

    error = nil;
    HttpdnsHostObject *result = [[HttpdnsRequest new] lookupHostFromServer:originalHost
                                                                     error:&error
                                                    activatedServerIPIndex:newActivatedServerIPIndex queryIPType:queryIPType];
    if (error) {
        HttpdnsLogDebug("Internal request for %@ error: %@", cacheKey, error);

        return [self executeRequest:originalHost
                         retryCount:(hasRetryedCount + 1)
             activatedServerIPIndex:activatedServerIPIndex
                              error:error
                        queryIPType:queryIPType];
    }

    dispatch_async(_syncDispatchQueue, ^{
        HttpdnsLogDebug("Internal request for %@ finished, result: %@", cacheKey, result);
        [self mergeLookupResultToManager:result forHost:cacheKey];
    });
    return result;
}

- (BOOL)isHostsNumberLimitReached {
    if ([HttpdnsUtil safeCountFromDict:_hostManagerDict] >= HTTPDNS_MAX_MANAGE_HOST_NUM) {
        HttpdnsLogDebug("Can't handle more than %d hosts due to the software configuration.", HTTPDNS_MAX_MANAGE_HOST_NUM);
        return YES;
    }
    return NO;
}

- (void)setExpiredIPEnabled:(BOOL)enable {
    _isExpiredIPEnabled = enable;
}

- (void)setCachedIPEnabled:(BOOL)enable {
    [self _setCachedIPEnabled:enable];
    [self cleanAllExpiredHostRecordsAsyncIfNeeded];
    [self loadIPsFromCacheAsyncIfNeeded];
}

- (void)_setCachedIPEnabled:(BOOL)enable {
    _cachedIPEnabled = enable;
}

- (BOOL)_getCachedIPEnabled {
    return _cachedIPEnabled;
}


- (void)_setRegin:(NSString *)region {
    if (!region) {
        region = ALICLOUD_DEFAULT_REGION;
    }
    _customRegion = region;
}

- (void)setPreResolveAfterNetworkChanged:(BOOL)enable {
    _isPreResolveAfterNetworkChangedEnabled = enable;
}

- (void)networkChanged:(NSNotification *)notification {
    NSNumber *networkStatus = [notification object];

    [HttpdnsgetNetworkInfoHelper updateNetworkStatus:(AlicloudNetworkStatus)[networkStatus intValue]];

    __block NSString *statusString = nil;
    switch ([networkStatus longValue]) {
        case 0:
            statusString = @"None";
            break;
        case 1:
            statusString = @"Wifi";
            break;
        case 3:
            statusString = @"3G";
            break;
        default:
            statusString = @"Unknown";
            break;
    }

    @try {
        HttpdnsLogDebug("Network changed, status: %@(%ld), lastNetworkStatus: %ld", statusString, [networkStatus longValue], _lastNetworkStatus);
    } @catch (NSException *exception) {
    }

    if (_lastNetworkStatus != [networkStatus longValue]) {
        dispatch_async(_syncDispatchQueue, ^{
            if (![statusString isEqualToString:@"None"]) {
                NSArray *hostArray = [HttpdnsUtil safeAllKeysFromDict:self->_hostManagerDict];
                [self cleanAllHostMemoryCache];
                [self resetServerDisableDate];
                //同步操作，防止网络请求成功，更新后，缓存数据再覆盖掉。
                [self loadIPsFromCacheSyncIfNeeded];
                if (self->_isPreResolveAfterNetworkChangedEnabled == YES) {
                    @try {
                        HttpdnsLogDebug("Network changed, pre resolve for hosts: %@", hostArray);
                    } @catch (NSException *exception) {
                    }

                    [self addPreResolveHosts:hostArray queryType:HttpdnsQueryIPTypeAuto];
                }
            }
        });
    }
    _lastNetworkStatus = [networkStatus longValue];
}

#pragma mark -
#pragma mark - disable status Setter and Getter Method

- (dispatch_queue_t)cacheQueue {
    if (!_cacheQueue) {
        _cacheQueue =
        dispatch_queue_create("com.alibaba.sdk.httpdns.cacheDisableStatusQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _cacheQueue;
}

- (void)snifferIfNeededWithHost:(NSString *)host activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    if (!_serverDisable) {
        return;
    }
    NSString * CopyHost = host;
    NSArray *hostArray= [host componentsSeparatedByString:@"]"];
    host = [hostArray lastObject];
    //获取当前域名的查询策略
    HttpdnsQueryIPType queryIPType = [[HttpdnsIPv6Manager sharedInstance] getQueryHostIPType:host];
    [self executeRequest:CopyHost retryCount:0 activatedServerIPIndex:activatedServerIPIndex error:nil queryIPType:queryIPType];
}

- (void)setServerDisable:(BOOL)serverDisable host:(NSString *)host {
    if (serverDisable) {
        HttpdnsLogDebug("if set serverDisable to YES, you must set the activatedServerIPIndex");
    }
    [self setServerDisable:serverDisable host:host activatedServerIPIndex:0];
}

- (void)setServerDisable:(BOOL)serverDisable host:(NSString *)host activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    dispatch_async(self.cacheQueue, ^{
        if (!serverDisable) {
            self->_lastServerDisableDate = nil;
        } else {
            self->_lastServerDisableDate = [NSDate date];
        }
    });
    if (_serverDisable == serverDisable) {
        return;
    }
    _serverDisable = serverDisable;
    if (!serverDisable) {
        [HttpdnsPersistenceUtils removeFile:self.disableStatusPath];
        return;
    }
    NSDictionary *json = @{
                           ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_KEY_STATUS : @(serverDisable)
                           };
    BOOL success = [HttpdnsPersistenceUtils saveJSON:json toPath:self.disableStatusPath];
    HttpdnsLogDebug("HTTPDNS disable status changes %@", success ? @"succeeded" : @"failed");
    if (serverDisable) {
        HttpdnsLogDebug("HTTPDNS is disabled");
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        NSInteger snifferServerIPIndex = [scheduleCenter nextServerIPIndexFromIPIndex:activatedServerIPIndex increase:2];
        [self snifferIfNeededWithHost:host activatedServerIPIndex:snifferServerIPIndex];
    }
}

- (NSDate *)lastServerDisableDate {
    __block NSDate *lastServerDisableDate = nil;
    dispatch_sync(self.cacheQueue, ^{
        lastServerDisableDate = _lastServerDisableDate;
    });
    return lastServerDisableDate;
}

- (void)resetServerDisableDate {
    dispatch_sync(self.cacheQueue, ^{
        _lastServerDisableDate = nil;
    });
}

- (NSString *)disableStatusPath {
    @synchronized(self) {
        if (_disableStatusPath) {
            return _disableStatusPath;
        }
        NSString *fileName = ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_FILE_NAME;
        NSString *fullPath = [[HttpdnsPersistenceUtils disableStatusPath] stringByAppendingPathComponent:fileName];
        _disableStatusPath = fullPath;
    }
    return _disableStatusPath;
}

#pragma mark -
#pragma mark - Flag for Disable and Sniffer Method

/**
 * AbleToSniffer means being able to sniffer
 * 可以进行嗅探行为，也即：异步请求服务端解析 DNS，且不执行重试逻辑。
 */
- (BOOL)isAbleToSniffer {
    //如果正在与SC进行同步，停止更新。
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    if (scheduleCenter.isConnectingWithScheduleCenter) {
        return NO;
    }
    // 需要考虑首次启动，值恒为nil，或者网络变化后，都可以允许网络探测
    if (!self.lastServerDisableDate) {
        return YES;
    }
    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:self.lastServerDisableDate];
    BOOL isAbleToSniffer = (timeInterval > ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL);    
    return isAbleToSniffer;
}

- (BOOL)isDisableToServer {
    if (_serverDisable && !self.isAbleToSniffer) {
        return YES;
    }
    return NO;
}

- (void)changeToNextServerIPIfNeededWithError:(NSError *)error
                                  fromIPIndex:(NSInteger)IPIndex
                                      isHTTPS:(BOOL)isHTTPS {
    if (!error) {
        return;
    }

    BOOL shouldChange = [self isTimeoutError:error isHTTPS:isHTTPS];
    if (shouldChange) {
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter changeToNextServerIPIndexFromIPIndex:IPIndex];
    }
}

- (BOOL)isTimeoutError:(NSError *)error isHTTPS:(BOOL)isHTTPS {
    //异步嗅探时是10006错误，重试时是10005错误
    //IPv6环境下，如果连接错误的域名，可能会有-1004错误
    BOOL canNotConnectServer = ALICLOUD_HTTPDNS_HTTP_CANNOT_CONNECT_SERVER_ERROR_CODE;
    BOOL isTimeout = (isHTTPS && (error.code == ALICLOUD_HTTPDNS_HTTPS_TIMEOUT_ERROR_CODE)) || (!isHTTPS && ((error.code == ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE) || (error.code == ALICLOUD_HTTPDNS_HTTP_STREAM_READ_ERROR_CODE)));
    return isTimeout || canNotConnectServer;
}

+ (dispatch_queue_t)hostCacheQueue {
    return _hostCacheQueue;
}

- (HttpdnsHostObject *)hostObjectFromCacheForHostName:(NSString *)hostName {
    //v1.6.1版本及以后，disable状态下了，不仅网络请求受限，缓存也同样受限。
    if (self.isServerDisable) {
        return nil;
    }
    HttpdnsHostObject *hostObject;
    hostObject = [HttpdnsUtil safeObjectForKey:hostName dict:_hostManagerDict];
    return hostObject;
}

- (void)loadIPsFromCacheAsyncIfNeeded {
    dispatch_async([[self class] hostCacheQueue], ^{
        [self loadIPsFromCacheSyncIfNeeded];
    });
}

- (void)cleanAllHostMemoryCache {
    [HttpdnsUtil safeRemoveAllObjectsFromDict:_hostManagerDict];
}

- (void)cleanCacheWithHostArray:(NSArray<NSString *> *)hostArray {
    if (![HttpdnsUtil isValidArray:hostArray]) {
        [self cleanAllHostMemoryCache];
    } else {
        for (NSString *host in hostArray) {
            if ([HttpdnsUtil isValidString:host]) {
                [HttpdnsUtil safeRemoveObjectForKey:host toDict:_hostManagerDict];
            }
        }
    }

    //清空数据库数据
    dispatch_async([[self class] hostCacheQueue], ^{
        //清空数据库数据
        [[HttpdnsHostCacheStore sharedInstance] cleanWithHosts:hostArray];
    });
}

- (void)loadIPsFromCacheSyncIfNeeded {
    dispatch_sync(_syncLoadCacheQueue, ^{
        if (!_cachedIPEnabled) {
            return;
        }
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
        NSArray<HttpdnsHostRecord *> *hostRecords = [hostCacheStore hostRecordsForCurrentCarrier];
        if (![HttpdnsUtil isValidArray:hostRecords]) {
            return;
        }
        for (HttpdnsHostRecord *hostRecord in hostRecords) {
            NSString *host = hostRecord.host;
            HttpdnsHostObject *hostObject = [HttpdnsHostObject hostObjectWithHostRecord:hostRecord];
            //从DB缓存中加载到内存里的数据，此时不会出现过期的情况，TTL时间后过期。
            [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
            [HttpdnsUtil safeAddValue:hostObject key:host toDict:_hostManagerDict];
            // 清除持久化缓存
            [hostCacheStore deleteHostRecordAndItsIPsWithHostRecordIDs:@[@(hostRecord.hostRecordId)]];
            [self aysncUpdateIPRankingWithResult:hostObject forHost:host];
        }
    });
}

- (void)cacheHostRecordAsyncIfNeededWithHost:(NSString *)host IPs:(NSArray<NSString *> *)IPs IP6s:(NSArray<NSString *> *)IP6s TTL:(int64_t)TTL ipRegion:(NSString *)ipRegion ip6Region:(NSString *)ip6Region {
    if (!_cachedIPEnabled) {
        return;
    }
    dispatch_async([HttpdnsRequestScheduler hostCacheQueue], ^{
        HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:host IPs:IPs IP6s:IP6s TTL:TTL ipRegion:ipRegion ip6Region:ip6Region];
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
        [hostCacheStore insertHostRecords:@[hostRecord]];
    });
}

- (void)sdnsCacheHostRecordAsyncIfNeededWithHost:(NSString *)host IPs:(NSArray<NSString *> *)IPs IP6s:(NSArray<NSString *> *)IP6s TTL:(int64_t)TTL withExtra:(NSDictionary *)extra ipRegion:(NSString *)ipRegion ip6Region:(NSString *)ip6Region {

    if (!_cachedIPEnabled) {
        return;
    }
    dispatch_async([HttpdnsRequestScheduler hostCacheQueue], ^{
        HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord sdnsHostRecordWithHost:host IPs:IPs IP6s:IP6s TTL:TTL Extra:extra ipRegion:ipRegion ip6Region:ip6Region];
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
        [hostCacheStore insertHostRecords:@[hostRecord]];
    });
}

// 清理过期数据的时机放在 `-loadIPsFromCacheSyncIfNeeded` 之前，应用启动后就进行，
- (void)cleanAllExpiredHostRecordsAsyncIfNeeded {
    if (!_cachedIPEnabled) {
        return;
    }
    dispatch_async([HttpdnsRequestScheduler hostCacheQueue], ^{
        [[HttpdnsHostCacheStore sharedInstance] cleanAllExpiredHostRecordsSync];
    });
}

// for test
- (NSString *)showMemoryCache {
    NSString *cacheDes;
    if ([HttpdnsUtil isValidDictionary:_hostManagerDict]) {
        cacheDes = [NSString stringWithFormat:@"%@", _hostManagerDict];
    }
    return cacheDes;
}

@end

@implementation HttpdnsRequestTestHelper

+ (void)zeroSnifferTimeForTest {
    ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 0;  /**< 0秒 */
}

@end
