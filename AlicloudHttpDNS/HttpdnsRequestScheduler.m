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
#import "HttpdnsLog.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsConstants.h"
#import "HttpdnsHostCacheStore.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsIPRecord.h"
#import "HttpdnsUtil.h"
#import "HttpDnsHitService.h"
#import "HttpdnsTCPSpeedTester.h"
#import "HttpdnsgetNetworkInfoHelper.h"
#import "HttpdnsIPv6Manager.h"

static NSString *const ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_KEY_STATUS = @"disable_status_key";
static NSString *const ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_FILE_NAME = @"disable_status";

NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED = @"203.107.1.1";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_1 = @"203.107.1.65";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_2 = @"203.107.1.34";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_3 = @"203.107.1.66";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_4 = @"203.107.1.33";
NSString *const ALICLOUD_HTTPDNS_HTTP_SERVER_PORT = @"80";
NSString *const ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT = @"443";

NSArray *ALICLOUD_HTTPDNS_SERVER_IP_LIST = nil;
NSTimeInterval ALICLOUD_HTTPDNS_SERVER_DISABLE_STATUS_CACHE_TIMEOUT_INTERVAL = 0;
static dispatch_queue_t _hostCacheQueue = NULL;
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

@end

@implementation HttpdnsRequestScheduler {
    long _lastNetworkStatus;
    BOOL _isExpiredIPEnabled;
    BOOL _isPreResolveAfterNetworkChangedEnabled;
    NSMutableDictionary *_hostManagerDict;
    dispatch_queue_t _syncDispatchQueue;
    NSOperationQueue *_asyncOperationQueue;
}

+ (void)initialize {
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _hostCacheQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.hostCacheQueue", DISPATCH_QUEUE_SERIAL);
        _syncLoadCacheQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.syncLoadCacheQueue", DISPATCH_QUEUE_SERIAL);
    });
    
    [self configureServerIPsAndResetActivatedIPTime];
}

- (instancetype)init {
    if (self = [super init]) {
        _lastNetworkStatus = 0;
        _isExpiredIPEnabled = NO;
        _IPRankingEnabled = NO;
        _isPreResolveAfterNetworkChangedEnabled = NO;
        _syncDispatchQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.sync", DISPATCH_QUEUE_SERIAL);
        _asyncOperationQueue = [[NSOperationQueue alloc] init];
        [_asyncOperationQueue setMaxConcurrentOperationCount:HTTPDNS_MAX_REQUEST_THREAD_NUM];
        _hostManagerDict = [[NSMutableDictionary alloc] init];
        [AlicloudIPv6Adapter getInstance];
        [AlicloudReachabilityManager shareInstance];
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
    ALICLOUD_HTTPDNS_SERVER_IP_LIST = @[
                                        ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED,
                                        ];
    ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 30; // 30 second
    ALICLOUD_HTTPDNS_SERVER_DISABLE_STATUS_CACHE_TIMEOUT_INTERVAL = 1 * 24 * 60 * 60; // one day
}

- (void)initServerDisableStatus {
    dispatch_async(self.cacheQueue, ^{
        NSDictionary *json = [HttpdnsPersistenceUtils getJSONFromDirectory:[HttpdnsPersistenceUtils disableStatusPath]
                                                                  fileName:ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_FILE_NAME
                                                                   timeout:ALICLOUD_HTTPDNS_SERVER_DISABLE_STATUS_CACHE_TIMEOUT_INTERVAL];
        if (!json) {
            //本地无缓存，常见于第一次安装，或者未发生过 DNS 故障。
            return;
        }
        
        @try {
            _serverDisable = [json[ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_KEY_STATUS] boolValue];
        } @catch (NSException *exception) {}
        
        if (_serverDisable) {
            HttpdnsLogDebug("HTTPDNS is disabled");
        }
    });
}

- (void)addPreResolveHosts:(NSArray *)hosts {
    if (![HttpdnsUtil isAbleToRequest]) {
        HttpdnsLogDebug("You should set accountID before adding PreResolveHosts");
        return;
    }
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
            if (!hostObject) {
                [self executeRequest:hostName synchronously:NO retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex];
                HttpdnsLogDebug("Pre resolve host %@ by async lookup.", hostName);
            } else if (![hostObject isQuerying]) {
                if ([hostObject isExpired]) {
                    HttpdnsLogDebug("%@ is expired, pre fetch again.", hostName);
                    [self executeRequest:hostName synchronously:NO retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex];
                } else {
                    HttpdnsLogDebug(@"%@ is omitted, expired: %d querying: %d", hostName, [hostObject isExpired], [hostObject isQuerying]);
                    continue;
                }
            }
        }
    });
}

#pragma mark -
#pragma mark - core method for all public query API

- (HttpdnsHostObject *)addSingleHostAndLookup:(NSString *)host synchronously:(BOOL)sync {
    if (![HttpdnsUtil isAbleToRequest]) {
        return nil;
    }
    if (![HttpdnsUtil isValidString:host]) {
        return nil;
    }
    __block HttpdnsHostObject *result = nil;
    __block BOOL needToQuery = NO;
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    @synchronized(self) {
        result = [self hostObjectFromCacheForHostName:host];
        HttpdnsLogDebug(@"Get from cache: %@", result);
        if (result == nil) {
            HttpdnsLogDebug("No available cache for %@ yet.", host);
            if ([self isHostsNumberLimitReached]) {
                return nil;
            }
            needToQuery = YES;
            HttpdnsHostObject *result =  [HttpdnsHostObject new];
            result.hostName = host;
            result.ips = @[];
            [result setQueryingState:YES];
            [_hostManagerDict setObject:result forKey:host];
        } else if (([result getIps].count == 0) && result.isQuerying ) {
            HttpdnsLogDebug("%@ queryingState: %d", host, [result isQuerying]);
            return nil;
        } else if ([result isExpired]) {
            HttpdnsLogDebug("%@ is expired, queryingState: %d", host, [result isQuerying]);
            if (_isExpiredIPEnabled) {
                needToQuery = NO;
                if (![result isQuerying]) {
                    [result setQueryingState:YES];
                    [self executeRequest:host synchronously:NO retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex];
                }
            } else {
                HttpdnsLogDebug("Expired IP is not accepted.");
                // For sync mode, We still send a synchronous request even it is in QUERYING state in order to avoid HOL blocking.
                needToQuery = YES;
                result = nil;
            }
        }
    }
    if (needToQuery) {
        if (![result isQuerying]) {
            [result setQueryingState:YES];
            if (sync) {
                return [self executeRequest:host synchronously:YES retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex];
            } else {
                [self executeRequest:host synchronously:NO retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex];
            }
        }
    } else {
        [self bizPerfGetIPWithHost:host success:YES];
    }
    return result;
}

- (void)bizPerfGetIPWithHost:(NSString *)host
                         success:(BOOL)success {
    BOOL cachedIPEnabled = [self _getCachedIPEnabled];
    [HttpDnsHitService bizPerfUserGetIPWithHost:host success:YES cacheOpen:cachedIPEnabled];
}

- (void)mergeLookupResultToManager:(HttpdnsHostObject *)result forHost:(NSString *)host {
    if (result) {
        [self setServerDisable:NO host:host];
        NSString *hostName = [result getHostName];
        HttpdnsHostObject *old;
        @synchronized(self) {
          old  = [_hostManagerDict objectForKey:hostName];
        }
        
        int64_t TTL = [result getTTL];
        int64_t lastLookupTime = [result getLastLookupTime];
        NSArray<NSString *> *IPStrings = [result getIPStrings];
        NSArray<HttpdnsIpObject *> *IPObjects = [result getIps];
        NSArray<HttpdnsIpObject *> *IP6Objects = [result getIp6s];
        if (old) {
            [old setTTL:TTL];
            [old setLastLookupTime:lastLookupTime];
            [old setIps:IPObjects];
            [old setQueryingState:NO];
            if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result] && [EMASTools isValidArray:IP6Objects]) {
                [old setIp6s:IP6Objects];
            }
            HttpdnsLogDebug("Update %@: %@", hostName, result);
        } else {
            HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
            [hostObject setHostName:host];
            [hostObject setLastLookupTime:lastLookupTime];
            [hostObject setTTL:TTL];
            [hostObject setIps:IPObjects];
            [hostObject setQueryingState:NO];
            if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result] && [EMASTools isValidArray:IP6Objects]) {
                [hostObject setIp6s:IP6Objects];
            }
            HttpdnsLogDebug("New resolved item: %@: %@", host, result);
            @synchronized(self) {
                [_hostManagerDict setObject:hostObject forKey:host];
            }
        }
        [self cacheHostRecordAsyncIfNeededWithHost:host IPs:IPStrings TTL:TTL];
        //TODO:
        [self aysncUpdateIPRankingWithResult:result forHost:host];
    } else {
        HttpdnsLogDebug("Can't resolve %@", host);
    }
}

//TODO:
- (void)aysncUpdateIPRankingWithResult:(HttpdnsHostObject *)result forHost:(NSString *)host {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        [self syncUpdateIPRankingWithResult:result forHost:host];
    });
}

- (void)syncUpdateIPRankingWithResult:(HttpdnsHostObject *)result forHost:(NSString *)host {
    if (!self.IPRankingEnabled) {
        return;
    }
    NSString *hostName = [result getHostName];
    NSArray<NSString *> *IPStrings = [result getIPStrings];
    NSArray *sortedIps = [[HttpdnsTCPSpeedTester new] ipRankingWithIPs:IPStrings host:hostName];
    [self updateHostManagerDictWithIPs:sortedIps host:host];
}

- (void)updateHostManagerDictWithIPs:(NSArray *)IPs host:(NSString *)host {
    if (!self.IPRankingEnabled) {
        return;
    }
    HttpdnsHostObject *hostObject;
    @synchronized(self) {
     hostObject = [_hostManagerDict objectForKey:host];
    }
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
            [ipObject setIp:[[AlicloudIPv6Adapter getInstance] handleIpv4Address:ip]];
            [ipArray addObject:ipObject];
        }
        [hostObject setIps:ipArray];
        [_hostManagerDict setObject:hostObject forKey:host];
    }
}

/*!
 * 用户访问引发的嗅探超时的情况，和重试引起的主动嗅探都会访问该方法，但是主动嗅探场景会在 `-[setServerDisable:]` 里直接返回。
 *
 if (_serverDisable == serverDisable) { return; }
 */
- (void)canNotResolveHost:(NSString *)host error:(NSError *)error isRetry:(BOOL)isRetry activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    NSDictionary *userInfo = error.userInfo;
    [HttpDnsHitService bizErrSrvWithSrvAddrIndex:activatedServerIPIndex errCode:error.code errMsg:error.description];
    //403 ServiceLevelDeny 错误强制更新，不触发disable机制。
    BOOL isServiceLevelDeny;
    @try {
        NSString *errorMessage = userInfo[ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY];
        isServiceLevelDeny = [errorMessage isEqualToString:ALICLOUD_HTTPDNS_ERROR_SERVICE_LEVEL_DENY];
    } @catch (NSException *exception) {}
    if (isServiceLevelDeny) {
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter forceUpdateIpListAsync];
        return;
    }
    
    BOOL isTimeoutError = [self isTimeoutError:error isHTTPS:HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED];
    if (isRetry && isTimeoutError) {
        [HttpDnsHitService bizLocalDisableWithHost:host srvAddrIndex:activatedServerIPIndex];
        [self setServerDisable:YES host:host activatedServerIPIndex:activatedServerIPIndex];
    }
    [self mergeLookupResultToManager:nil forHost:host];
}

- (HttpdnsHostObject *)executeRequest:(NSString *)host
                        synchronously:(BOOL)sync
                           retryCount:(int)hasRetryedCount
               activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    return [self executeRequest:host synchronously:sync retryCount:hasRetryedCount activatedServerIPIndex:activatedServerIPIndex error:nil];
}

- (HttpdnsHostObject *)executeRequest:(NSString *)host
                        synchronously:(BOOL)sync
                           retryCount:(int)hasRetryedCount
               activatedServerIPIndex:(NSInteger)activatedServerIPIndex
                                error:(NSError *)error {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    if (![HttpdnsUtil isAbleToRequest]) {
        return nil;
    }
    if (scheduleCenter.isStopService) {
        return nil;
    }
    BOOL isRetry = NO;
    if (hasRetryedCount == 0) {
        error = nil;
    } else {
        isRetry = YES;
    }
    if (hasRetryedCount > HTTPDNS_MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogDebug("Retry count exceed limit, abort!");
        [self canNotResolveHost:host error:error isRetry:isRetry activatedServerIPIndex:activatedServerIPIndex];
        return nil;
    }
    
    [HttpDnsService statIfNeeded];
    
    if ([self isDisableToServer]) {
        return nil;
    }
    
    /**
     *
     * 以下为：网络 Disable 且 AbleToSniffer、网络正常。
     * 可能发生的情况如下所示：

     ------------ | 网络 Disable且 AbleToSniffer | 网络正常
     -------------|---------------------------- | -------------
          同步     |     嗅探（不重试的异步）       | 正常（重试的同步）
          异步     |     嗅探（不重试的异步）       | 正常（重试的异步）
     
     * 我们可以总结出来：以下方法的情况中，除了同步且网络正常的情况，其余都需要走异步请求，且异步中，唯一的区别在于，是否需要重试。
     */
    
    NSInteger newActivatedServerIPIndex = [scheduleCenter nextServerIPIndexFromIPIndex:activatedServerIPIndex increase:hasRetryedCount];
    
    BOOL shouldRetry = !self.isServerDisable;
    
    if (sync && shouldRetry) {
        NSError *error;
        HttpdnsLogDebug("Sync request for %@ starts.", host);
        HttpdnsHostObject *result = [[HttpdnsRequest new] lookupHostFromServer:host
                                                            error:&error
                                           activatedServerIPIndex:newActivatedServerIPIndex];
        if (error) {
            HttpdnsLogDebug("Sync request for %@ error: %@", host, error);
            return [self executeRequest:host
                          synchronously:YES
                             retryCount:(hasRetryedCount + 1)
                 activatedServerIPIndex:activatedServerIPIndex
                                  error:error];
        } else {
            dispatch_async(_syncDispatchQueue, ^{
                HttpdnsLogDebug("Sync request for %@ finishes.", host);
                [self mergeLookupResultToManager:result forHost:host];
            });
            return result;
        }
    }
    
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        if ([self isDisableToServer]) {
            return;
        }
        NSError *error;
        HttpdnsLogDebug("Async request for %@ starts...", host);
        HttpdnsHostObject *result = [[HttpdnsRequest new] lookupHostFromServer:host
                                                                         error:&error
                                                        activatedServerIPIndex:newActivatedServerIPIndex];
        if (error) {
            HttpdnsLogDebug("Async request for %@ error: %@", host, error);
            
            if (shouldRetry) {
                [self executeRequest:host
                       synchronously:NO
                          retryCount:hasRetryedCount + 1
              activatedServerIPIndex:activatedServerIPIndex
                 error:error];
            } else {
                [self canNotResolveHost:host error:error isRetry:isRetry activatedServerIPIndex:activatedServerIPIndex];
            }
        } else {
            dispatch_sync(_syncDispatchQueue, ^{
                HttpdnsLogDebug("Async request for %@ finishes.", host);
                [self mergeLookupResultToManager:result forHost:host];
            });
        }
    }];
    [_asyncOperationQueue addOperation:operation];
    
    return nil;
}

- (BOOL)isHostsNumberLimitReached {
    if ([_hostManagerDict count] >= HTTPDNS_MAX_MANAGE_HOST_NUM) {
        HttpdnsLogDebug(@"Can't handle more than %d hosts due to the software configuration.", HTTPDNS_MAX_MANAGE_HOST_NUM);
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
   
    HttpdnsLogDebug(@"Network changed, status: %@(%ld), lastNetworkStatus: %ld", statusString, [networkStatus longValue], _lastNetworkStatus);
    if (_lastNetworkStatus != [networkStatus longValue]) {
        dispatch_async(_syncDispatchQueue, ^{
            if (![statusString isEqualToString:@"None"]) {
                NSArray *hostArray = [_hostManagerDict allKeys];
                [self cleanAllHostMemoryCache];
                //同步操作，防止网络请求成功，更新后，缓存数据再覆盖掉。
                [self loadIPsFromCacheSyncIfNeeded];
                if (_isPreResolveAfterNetworkChangedEnabled == YES) {
                    HttpdnsLogDebug(@"Network changed, pre resolve for hosts: %@", hostArray);
                    [self addPreResolveHosts:hostArray];
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
    [HttpDnsHitService bizSnifferWithHost:host
                         srvAddrIndex:activatedServerIPIndex];
    [self executeRequest:host synchronously:NO retryCount:0 activatedServerIPIndex:activatedServerIPIndex];
}

- (void)setServerDisable:(BOOL)serverDisable host:(NSString *)host {
    if (serverDisable) {
        HttpdnsLogDebug(@"if set serverDisable to YES, you must set the activatedServerIPIndex");
    }
    [self setServerDisable:serverDisable host:host activatedServerIPIndex:0];
}

- (void)setServerDisable:(BOOL)serverDisable host:(NSString *)host activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    dispatch_async(self.cacheQueue, ^{
        if (!serverDisable) {
            _lastServerDisableDate = nil;
        } else {
            _lastServerDisableDate = [NSDate date];
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
    HttpdnsLogDebug(@"HTTPDNS disable status changes %@", success ? @"succeeded" : @"failed");
    if (serverDisable) {
        HttpdnsLogDebug("HTTPDNS is disabled");
        [_asyncOperationQueue cancelAllOperations];
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
    //需要考虑首次启动，值恒为nil，或者网络正常情况下。
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
    @synchronized(self) {
        hostObject = [_hostManagerDict objectForKey:hostName];
    }
    return hostObject;
}

- (void)loadIPsFromCacheAsyncIfNeeded {
    dispatch_async([[self class] hostCacheQueue], ^{
        [self loadIPsFromCacheSyncIfNeeded];
    });
}

- (void)cleanAllHostMemoryCache {
    @synchronized(self) {
    [_hostManagerDict removeAllObjects];
    }
}

- (void)loadIPsFromCacheSyncIfNeeded {
    dispatch_sync(_syncLoadCacheQueue, ^{
        if (!_cachedIPEnabled) {
            return;
        }
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore new];
        NSArray<HttpdnsHostRecord *> *hostRecords = [hostCacheStore hostRecordsForCurrentCarrier];
        if (![HttpdnsUtil isValidArray:hostRecords]) {
            return;
        }
        for (HttpdnsHostRecord *hostRecord in hostRecords) {
            NSString *host = hostRecord.host;
            HttpdnsHostObject *hostObject = [HttpdnsHostObject hostObjectWithHostRecord:hostRecord];
            //从DB缓存中加载到内存里的数据，此时不会出现过期的情况，TTL时间后过期。
            [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
            [_hostManagerDict setObject:hostObject forKey:host];
            
            [self aysncUpdateIPRankingWithResult:hostObject forHost:host];
        }
    });
}

- (void)cacheHostRecordAsyncIfNeededWithHost:(NSString *)host IPs:(NSArray<NSString *> *)IPs TTL:(int64_t)TTL {
    if (!_cachedIPEnabled) {
        return;
    }
    dispatch_async([HttpdnsRequestScheduler hostCacheQueue], ^{
        HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:host IPs:IPs TTL:TTL];
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore new];
        [hostCacheStore insertHostRecords:@[hostRecord]];
    });
}

//清理过期数据的时机放在 `-loadIPsFromCacheSyncIfNeeded` 之前，应用启动后就进行，
- (void)cleanAllExpiredHostRecordsAsyncIfNeeded {
    if (!_cachedIPEnabled) {
        return;
    }
    dispatch_async([HttpdnsRequestScheduler hostCacheQueue], ^{
        [[HttpdnsHostCacheStore new] cleanAllExpiredHostRecordsSync];
    });
}

@end

@implementation HttpdnsRequestTestHelper

+ (void)zeroSnifferTimeForTest {
    ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 0;  /**< 0秒 */
}

@end
