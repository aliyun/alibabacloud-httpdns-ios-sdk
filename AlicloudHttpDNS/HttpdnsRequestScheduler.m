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

#import "HttpdnsModel.h"
#import "HttpdnsRequest.h"
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsConfig.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsServiceProvider_Internal.h"

static NSString *const ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_KEY_STATUS = @"disable_status_key";
static NSString *const ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_FILE_NAME = @"disable_status";

//#define DEBUG 1
#ifdef DEBUG

NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED = @"10.125.65.207";
 NSString *const ALICLOUD_HTTPDNS_SERVER_IP_1 = @"10.125.65.207";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_2 = @"10.125.65.207";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_3 = @"10.125.65.207";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_4 = @"10.125.65.207";
NSString *const ALICLOUD_HTTPDNS_HTTP_SERVER_PORT = @"8100";
NSString *const ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT = @"8100";

#else

NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED = @"203.107.1.1";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_1 = @"203.107.1.65";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_2 = @"203.107.1.34";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_3 = @"203.107.1.66";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_4 = @"203.107.1.33";
NSString *const ALICLOUD_HTTPDNS_HTTP_SERVER_PORT = @"80";
NSString *const ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT = @"443";

#endif

NSArray *ALICLOUD_HTTPDNS_SERVER_IP_LIST = nil;
NSInteger ALICLOUD_HTTPDNS_RESET_ACTIVATED_SERVER_IP_TIME_HOURS = 0;
/**
 * Disable状态开始30秒后可以进行“嗅探”行为
 */
static NSTimeInterval ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 0;

@interface HttpdnsRequestScheduler()

/**
 * disable 状态置位的逻辑会在 `-mergeLookupResultToManager:forHost:` 中执行。
 */
@property (nonatomic, assign, getter=isServerDisable) BOOL serverDisable;
@property (nonatomic, strong) NSDate *lastServerDisableDate;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, copy) NSString *disableStatusPath;
@property (nonatomic, strong) dispatch_queue_t cacheActivatedServerIPStatusQueue;
@property (nonatomic, copy) NSString *activatedIPIndexPath;


@end

@implementation HttpdnsRequestScheduler {
    long _lastNetworkStatus;
    BOOL _isExpiredIPEnabled;
    BOOL _isPreResolveAfterNetworkChangedEnabled;
    NSMutableDictionary *_hostManagerDict;
    dispatch_queue_t _syncDispatchQueue;
    NSOperationQueue *_asyncOperationQueue;
}
@synthesize activatedServerIPIndex = _activatedServerIPIndex;

- (instancetype)init {
    if (self = [super init]) {
        [[self class] configureServerIPsAndResetActivatedIPTime];
        _lastNetworkStatus = 0;
        _isExpiredIPEnabled = NO;
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
        _activatedServerIPIndex = 0;
        [self initActivatedServerIPIndex];
        _testHelper = [[HttpdnsRequestTestHelper alloc] init];
    }
    return self;
}

+ (void)configureServerIPsAndResetActivatedIPTime {
    ALICLOUD_HTTPDNS_SERVER_IP_LIST = @[
                                        ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED,
                                        ALICLOUD_HTTPDNS_SERVER_IP_1,
                                        ALICLOUD_HTTPDNS_SERVER_IP_2,
                                        ALICLOUD_HTTPDNS_SERVER_IP_3,
                                        ALICLOUD_HTTPDNS_SERVER_IP_4
                                        ];
    ALICLOUD_HTTPDNS_RESET_ACTIVATED_SERVER_IP_TIME_HOURS = 2;
    ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 30;
}

- (void)initActivatedServerIPIndex {
    dispatch_async(self.cacheActivatedServerIPStatusQueue, ^{
        NSInteger oldServerIPIndex = _activatedServerIPIndex;
        [HttpdnsPersistenceUtils deleteFilesInDirectory:[HttpdnsPersistenceUtils activatedIPIndexPath] moreThanHours:ALICLOUD_HTTPDNS_RESET_ACTIVATED_SERVER_IP_TIME_HOURS];
        BOOL isfileExist = [HttpdnsPersistenceUtils fileExist:self.activatedIPIndexPath];
        if (!isfileExist) {
            return;
        }
        NSDictionary *json = [HttpdnsPersistenceUtils getJSONFromPath:self.activatedIPIndexPath];
        if (!json) {
            return;
        }
        
        @try {
            _activatedServerIPIndex = [json[ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_KEY] integerValue];
        } @catch (NSException *exception) {}
        
        if (_activatedServerIPIndex != oldServerIPIndex) {
            HttpdnsLogDebug("HTTPDNS activated IP changed");
        }
    });
}

- (void)initServerDisableStatus {
    dispatch_async(self.cacheQueue, ^{
        [HttpdnsPersistenceUtils deleteFilesInDirectory:[HttpdnsPersistenceUtils disableStatusPath] moreThanDays:1];
        BOOL isfileExist = [HttpdnsPersistenceUtils fileExist:self.disableStatusPath];
        if (!isfileExist) {
            return;
        }
        NSDictionary *json = [HttpdnsPersistenceUtils getJSONFromPath:self.disableStatusPath];
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
    dispatch_async(_syncDispatchQueue, ^{
        for (NSString *hostName in hosts) {
            if ([self isHostsNumberLimitReached]) {
                break;
            }
            HttpdnsHostObject *hostObject = [_hostManagerDict objectForKey:hostName];
            if (hostObject) {
                if ([hostObject isExpired] && ![hostObject isQuerying]) {
                    HttpdnsLogDebug("%@ is expired, pre fetch again.", hostName);
                    [self executeRequest:hostName synchronously:NO retryCount:0 activatedServerIPIndex:self.activatedServerIPIndex];
                } else {
                    HttpdnsLogDebug(@"%@ is omitted, expired: %d querying: %d", hostName, [hostObject isExpired], [hostObject isQuerying]);
                    continue;
                }
            } else {
                [self executeRequest:hostName synchronously:NO retryCount:0 activatedServerIPIndex:self.activatedServerIPIndex];
                HttpdnsLogDebug("Pre resolve host %@ by async lookup.", hostName);
            }
        }
    });
}

- (HttpdnsHostObject *)addSingleHostAndLookup:(NSString *)host synchronously:(BOOL)sync {
    __block HttpdnsHostObject *result = nil;
    __block BOOL needToQuery = NO;
    dispatch_sync(_syncDispatchQueue, ^{
        result = [_hostManagerDict objectForKey:host];
        HttpdnsLogDebug(@"Get from cache: %@", result);
        if (result == nil) {
            HttpdnsLogDebug("No available cache for %@ yet.", host);
            if ([self isHostsNumberLimitReached]) {
                return;
            }
            needToQuery = YES;
        } else if ([result isExpired]) {
            HttpdnsLogDebug("%@ is expired, queryingState: %d", host, [result isQuerying]);
            if (_isExpiredIPEnabled) {
                needToQuery = NO;
                if (![result isQuerying]) {
                    [result setQueryingState:YES];
                    [self executeRequest:host synchronously:NO retryCount:0 activatedServerIPIndex:self.activatedServerIPIndex];
                }
            } else {
                HttpdnsLogDebug("Expired IP is not accepted.");
                // For sync mode, We still send a synchronous request even it is in QUERYING state in order to avoid HOL blocking.
                needToQuery = YES;
                result = nil;
            }
        }
        if (needToQuery) {
            [result setQueryingState:YES];
        }
    });
    if (needToQuery) {
        if (sync) return [self executeRequest:host synchronously:YES retryCount:0 activatedServerIPIndex:self.activatedServerIPIndex];
        else [self executeRequest:host synchronously:NO retryCount:0 activatedServerIPIndex:self.activatedServerIPIndex];
    }
    return result;
}

- (void)mergeLookupResultToManager:(HttpdnsHostObject *)result forHost:(NSString *)host {
    if (result) {
        [self setServerDisable:NO host:host];
        NSString *hostName = [result getHostName];
        HttpdnsHostObject * old = [_hostManagerDict objectForKey:hostName];
        if (old) {
            [old setTTL:[result getTTL]];
            [old setLastLookupTime:[result getLastLookupTime]];
            [old setIps:[result getIps]];
            [old setQueryingState:NO];
            HttpdnsLogDebug("Update %@: %@", hostName, result);
        } else {
            HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
            [hostObject setHostName:host];
            [hostObject setLastLookupTime:[result getLastLookupTime]];
            [hostObject setTTL:[result getTTL]];
            [hostObject setIps:[result getIps]];
            [hostObject setQueryingState:NO];
            HttpdnsLogDebug("New resolved item: %@: %@", host, result);
            [_hostManagerDict setObject:hostObject forKey:host];
        }
    } else {
        HttpdnsLogDebug("Can't resolve %@", host);
    }
}

- (void)canNotResolveHost:(NSString *)host error:(NSError *)error isRetry:(BOOL)isRetry activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    dispatch_async(_syncDispatchQueue, ^{
        BOOL isTimeoutError = [self isTimeoutError:error isHTTPS:HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED];
        if (isRetry && isTimeoutError) {
            [self setServerDisable:YES host:host activatedServerIPIndex:activatedServerIPIndex];
        }
        [self mergeLookupResultToManager:nil forHost:host];
    });
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
    
    HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
    NSInteger newActivatedServerIPIndex = activatedServerIPIndex + hasRetryedCount;
    
    if (sync && !self.isServerDisable) {
        NSError *error;
        HttpdnsLogDebug("Sync request for %@ starts.", host);
        HttpdnsHostObject *result = [request lookupHostFromServer:host
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
        HttpdnsHostObject *result = [request lookupHostFromServer:host
                                                            error:&error
                                           activatedServerIPIndex:newActivatedServerIPIndex];
        if (error) {
            HttpdnsLogDebug("Async request for %@ error: %@", host, error);
            BOOL shouldRetry = !self.isServerDisable;
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

- (void)setPreResolveAfterNetworkChanged:(BOOL)enable {
    _isPreResolveAfterNetworkChangedEnabled = enable;
}

- (void)networkChanged:(NSNotification *)notification {
    NSNumber *networkStatus = [notification object];
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
                NSArray * hostArray = [_hostManagerDict allKeys];
                [_hostManagerDict removeAllObjects];
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
    if (!self.serverDisable) {
        return;
    }
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
        if (!_serverDisable) {
            _lastServerDisableDate = nil;
        } else {
            _lastServerDisableDate = [NSDate date];
        }
        
        if (_serverDisable == serverDisable) {
            return;
        }
        _serverDisable = serverDisable;
        if (!_serverDisable) {
            [HttpdnsPersistenceUtils removeFile:self.disableStatusPath];
            return;
        }
        NSDictionary *json = @{
                               ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_KEY_STATUS : @(serverDisable)
                               };
        BOOL success = [HttpdnsPersistenceUtils saveJSON:json toPath:self.disableStatusPath];
        HttpdnsLogDebug(@"HTTPDNS disable status changes %@", success ? @"succeeded" : @"failed");
    });
    
    if (serverDisable) {
        [_asyncOperationQueue cancelAllOperations];
        NSInteger snifferServerIPIndex = [self nextServerIPIndexFromIPIndex:activatedServerIPIndex increase:2];
        [self snifferIfNeededWithHost:host activatedServerIPIndex:snifferServerIPIndex];
        HttpdnsLogDebug("HTTPDNS is disabled");
    }
}

- (BOOL)isServerDisable {
    __block BOOL isServerDisable = NO;
    dispatch_sync(self.cacheQueue, ^{
        isServerDisable = _serverDisable;
    });
    return isServerDisable;
}

- (NSDate *)lastServerDisableDate {
    __block NSDate *lastServerDisableDate = nil;
    dispatch_sync(self.cacheQueue, ^{
        lastServerDisableDate = _lastServerDisableDate;
    });
    return lastServerDisableDate;
}

- (NSString *)disableStatusPath {
    if (_disableStatusPath) {
        return _disableStatusPath;
    }
    NSString *fileName = ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_FILE_NAME;
    NSString *fullPath = [[HttpdnsPersistenceUtils disableStatusPath] stringByAppendingPathComponent:fileName];
    _disableStatusPath = fullPath;
    return _disableStatusPath;
}

#pragma mark -
#pragma mark - Flag for Disable and Sniffer Method

/**
 * AbleToSniffer means being able to sniffer
 * 可以进行嗅探行为，也即：异步请求服务端解析 DNS，且不执行重试逻辑。
 */
- (BOOL)isAbleToSniffer {
    //需要考虑首次启动，值恒为nil，或者网络正常情况下。
    if (!self.lastServerDisableDate) {
        return YES;
    }
    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:self.lastServerDisableDate];
    BOOL isAbleToSniffer = timeInterval > ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL;
    return isAbleToSniffer;
}

- (BOOL)isDisableToServer {
    if (self.isServerDisable && !self.isAbleToSniffer) {
        return YES;
    }
    return NO;
}

- (void)changeToNextServerIPIndexFromIPIndex:(NSInteger)IPIndex {
    NSInteger nextServerIPIndex = [self nextServerIPIndexFromIPIndex:IPIndex increase:1];
    self.activatedServerIPIndex = nextServerIPIndex;
}

- (NSString *)getActivatedServerIPWithIndex:(NSInteger)index {
    NSString *serverIP = nil;
    @try {
        serverIP = ALICLOUD_HTTPDNS_SERVER_IP_LIST[index];
    } @catch (NSException *exception) {
        serverIP = ALICLOUD_HTTPDNS_SERVER_IP_LIST[0];
    }
    return serverIP;
}

- (NSInteger)nextServerIPIndexFromIPIndex:(NSInteger)IPIndex increase:(NSInteger)increase {
    NSInteger nextServerIPIndex = ((IPIndex + increase) % ALICLOUD_HTTPDNS_SERVER_IP_LIST.count);
    return nextServerIPIndex;
}

- (void)setActivatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    dispatch_async(self.cacheActivatedServerIPStatusQueue, ^{
        if (_activatedServerIPIndex == activatedServerIPIndex) {
            return;
        }
        _activatedServerIPIndex = activatedServerIPIndex;
        
        if (activatedServerIPIndex == 0) {
            [HttpdnsPersistenceUtils removeFile:self.activatedIPIndexPath];
            return;
        }
        
        NSDictionary *json = @{
                               ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_KEY : @(activatedServerIPIndex)
                               };
        BOOL success = [HttpdnsPersistenceUtils saveJSON:json toPath:self.activatedIPIndexPath];
        HttpdnsLogDebug(@"HTTPDNS activated IP changes %@, index is %@", success ? @"succeeded" : @"failed", @(activatedServerIPIndex));
    });
}

- (NSInteger)activatedServerIPIndex {
    __block NSInteger activatedServerIPIndex = 0;
    dispatch_sync(self.cacheActivatedServerIPStatusQueue, ^{
        activatedServerIPIndex = _activatedServerIPIndex;
    });
    return activatedServerIPIndex;
}

- (dispatch_queue_t)cacheActivatedServerIPStatusQueue {
    if (!_cacheActivatedServerIPStatusQueue) {
        _cacheActivatedServerIPStatusQueue =
        dispatch_queue_create("com.alibaba.sdk.httpdns.cacheActivatedServerIPStatusQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _cacheActivatedServerIPStatusQueue;
}

#pragma mark -
#pragma mark - Activated IP Index Method


- (NSString *)activatedIPIndexPath {
    if (_activatedIPIndexPath) {
        return _activatedIPIndexPath;
    }
    NSString *fileName = ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_CACHE_FILE_NAME;
    NSString *fullPath = [[HttpdnsPersistenceUtils activatedIPIndexPath] stringByAppendingPathComponent:fileName];
    _activatedIPIndexPath = fullPath;
    return _activatedIPIndexPath;
}

- (void)changeToNextServerIPIfNeededWithError:(NSError *)error
                                  fromIPIndex:(NSInteger)IPIndex
                                      isHTTPS:(BOOL)isHTTPS {
    //异步嗅探时是10006错误，重试时是10005错误
    if (!error) {
        return;
    }
    
    BOOL shouldChange = [self isTimeoutError:error isHTTPS:isHTTPS];
    if (shouldChange) {
        [self changeToNextServerIPIndexFromIPIndex:IPIndex];
    }
}

- (BOOL)isTimeoutError:(NSError *)error isHTTPS:(BOOL)isHTTPS {
    BOOL isTimeout = (isHTTPS && (error.code == ALICLOUD_HTTPDNS_HTTPS_TIMEOUT_ERROR_CODE)) || (!isHTTPS && ((error.code == ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE) || (error.code == ALICLOUD_HTTPDNS_HTTP_STREAM_READ_ERROR_CODE)));
    return isTimeout;
}

@end

@implementation HttpdnsRequestTestHelper

- (void)setFirstIPWrongForTest {
    ALICLOUD_HTTPDNS_SERVER_IP_LIST = @[
                                        @"190.190.190.190",
                                        ALICLOUD_HTTPDNS_SERVER_IP_1,
                                        ALICLOUD_HTTPDNS_SERVER_IP_2,
                                        ALICLOUD_HTTPDNS_SERVER_IP_3,
                                        ALICLOUD_HTTPDNS_SERVER_IP_4
                                        ];
}

- (void)shortResetActivatedIPTimeForTest {
    ALICLOUD_HTTPDNS_RESET_ACTIVATED_SERVER_IP_TIME_HOURS = 1/3600;  /**< 1秒 */
}

- (void)setTwoFirstIPWrongForTest {
    ALICLOUD_HTTPDNS_SERVER_IP_LIST = @[
                                        @"190.190.190.190",
                                        @"191.191.191.191",
                                        ALICLOUD_HTTPDNS_SERVER_IP_2,
                                        ALICLOUD_HTTPDNS_SERVER_IP_3,
                                        ALICLOUD_HTTPDNS_SERVER_IP_4
                                        ];
}

- (void)setFourFirstIPWrongForTest {
    ALICLOUD_HTTPDNS_SERVER_IP_LIST = @[
                                        @"190.190.190.190",
                                        @"191.191.191.191",
                                        @"192.192.192.192",
                                        @"193.193.193.193",
                                        ALICLOUD_HTTPDNS_SERVER_IP_4,
                                        ];
}

- (void)zeroSnifferTimeForTest {
    ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 0;  /**< 1秒 */
}

@end
