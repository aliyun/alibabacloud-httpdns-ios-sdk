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
#import "HttpdnsHostObject.h"
#import "HttpdnsHostResolver.h"
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

static dispatch_queue_t _memoryCacheSerialQueue = NULL;
static dispatch_queue_t _persistentCacheConcurrentQueue = NULL;
static dispatch_queue_t _asyncResolveHostQueue = NULL;

typedef struct {
    BOOL isResultUsable;
    BOOL isResolvingRequired;
} HostObjectExamingResult;

@interface HttpdnsRequestScheduler()

/**
 * disable 状态置位的逻辑会在 `-mergeLookupResultToManager` 中执行。
 */
@property (nonatomic, assign, getter=isServerDisable) BOOL serverDisable;
@property (nonatomic, strong) NSDate *lastServerDisableDate;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, copy) NSString *disableStatusPath;
@property (nonatomic, assign) BOOL persistentCacheIpEnabled;
@property (nonatomic, copy) NSString *customRegion; //当前设置的region

@end

@implementation HttpdnsRequestScheduler {
    long _lastNetworkStatus;
    BOOL _isExpiredIPEnabled;
    BOOL _isPreResolveAfterNetworkChangedEnabled;
    NSMutableDictionary *_hostManagerDict;
    NSLock *_lock;
}

+ (void)initialize {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        _memoryCacheSerialQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.memoryCacheOperationQueue", DISPATCH_QUEUE_SERIAL);
        _persistentCacheConcurrentQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.persistentCacheOperationQueue", DISPATCH_QUEUE_CONCURRENT);
        _asyncResolveHostQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.asyncResolveHostQueue", DISPATCH_QUEUE_CONCURRENT);
    });

    [self configureServerIPsAndResetActivatedIPTime];
}

+ (void)configureServerIPsAndResetActivatedIPTime {
    // 默认的内置服务ipv4 地址 根据国际站来区分
    ALICLOUD_HTTPDNS_SERVER_IP_LIST = @[ALICLOUD_HTTPDNS_SERVER_IP_DEFAULT];

    // 默认的内置服务ipv6 地址 根据国际站来区分
    ALICLOUD_HTTPDNS_SERVER_IPV6_LIST = @[ALICLOUD_HTTPDNS_SERVER_IPV6_DEFAULT];

    // Disable状态开始30秒后可以进行“嗅探”行为
    ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 30;

    // sever disable状态缓存时间默认为1天
    ALICLOUD_HTTPDNS_SERVER_DISABLE_STATUS_CACHE_TIMEOUT_INTERVAL = 1 * 24 * 60 * 60;
}

- (instancetype)init {
    if (self = [super init]) {
        _lastNetworkStatus = [AlicloudReachabilityManager shareInstance].currentNetworkStatus;
        _isExpiredIPEnabled = NO;
        _IPRankingEnabled = NO;
        _isPreResolveAfterNetworkChangedEnabled = NO;
        _customRegion = [[NSUserDefaults standardUserDefaults] objectForKey:ALICLOUD_HTTPDNS_REGION_KEY];
        if (!_customRegion) {
            _customRegion = ALICLOUD_DEFAULT_REGION;
        }
        _hostManagerDict = [[NSMutableDictionary alloc] init];
        _lock = [[NSLock alloc] init];
        [AlicloudIPv6Adapter getInstance];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(networkChanged:)
                                                     name:ALICLOUD_NETWOEK_STATUS_NOTIFY
                                                   object:nil];
        [self initServerDisableStatus];
    }
    return self;
}

- (void)initServerDisableStatus {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.cacheQueue, ^{
        NSDictionary *json = [HttpdnsPersistenceUtils getJSONFromDirectory:[HttpdnsPersistenceUtils disableStatusPath]
                                                                  fileName:ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_FILE_NAME
                                                                   timeout:ALICLOUD_HTTPDNS_SERVER_DISABLE_STATUS_CACHE_TIMEOUT_INTERVAL];
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!json) {
            // 本地无缓存，常见于第一次安装，或者未发生过 DNS 故障。
            return;
        }

       strongSelf.serverDisable = [[HttpdnsUtil safeObjectForKey:ALICLOUD_HTTPDNS_SERVER_DISABLE_CACHE_KEY_STATUS dict:json] boolValue];
        if (strongSelf.serverDisable) {
            HttpdnsLogDebug("HTTPDNS is disabled");
        }
    });
}

- (void)addPreResolveHosts:(NSArray *)hosts queryType:(HttpdnsQueryIPType)queryType{
    if (![HttpdnsUtil isNotEmptyArray:hosts]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(_asyncResolveHostQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        for (NSString *hostName in hosts) {
            if ([self isHostsNumberLimitReached]) {
                break;
            }
            HttpdnsHostObject *hostObject = [HttpdnsUtil safeObjectForKey:hostName dict:strongSelf->_hostManagerDict];
            if (!hostObject
                || [hostObject isExpiredUnderQueryIpType:queryType]
                || [hostObject isRegionNotMatch:self.customRegion underQueryIpType:queryType]) {

                HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:hostName isBlockingRequest:NO queryIpType:queryType];
                [self resolveHost:request];
                HttpdnsLogDebug("Pre resolve host by async lookup, host: %@", hostName);
            }
        }
    });
}

#pragma mark - core method for all public query API
- (HttpdnsHostObject *)resolveHost:(HttpdnsRequest *)request {
    HttpdnsLogDebug("resolveHost, request: %@", request);

    NSString *host = request.host;
    NSString *cacheKey = request.cacheKey;

    if ([HttpdnsUtil isEmptyString:host]) {
        return nil;
    }

    __block HttpdnsHostObject *result = nil;
    dispatch_sync(_memoryCacheSerialQueue, ^{
        result = [HttpdnsUtil safeObjectForKey:cacheKey dict:_hostManagerDict];
        HttpdnsLogDebug("try to load from cache, cacheKey: %@, result: %@", cacheKey, result);

        if (!result) {
            // 在这里构造新的HttpdnsHostObject并置入缓存比较安全，因为这里被sync语义保护着
            // 如果后面merge的时候再构造，得重新做同步控制
            result = [HttpdnsHostObject new];
            result.ips = @[];
            result.ip6s = @[];
            result.hostName = host;
            result.extra = @{};
            [HttpdnsUtil safeAddValue:result key:cacheKey toDict:_hostManagerDict];
        }
    });

    HostObjectExamingResult examingResult = [self examineHttpdnsHostObject:result underQueryType:request.queryIpType];
    BOOL isResultUsable = examingResult.isResultUsable;
    BOOL isResolvingRequired = examingResult.isResolvingRequired;

    if (isResultUsable) {
        if (isResolvingRequired) {
            // 缓存结果可用，但是需要请求，因为缓存结果已经过期
            // 这种情况异步去解析就可以了
            [self determineResolvingHostNonBlocking:request];
        }
        // 因为缓存结果可用，可以立即返回
        return result;
    }

    if (request.isBlockingRequest) {
        // 缓存结果不可用，且是同步请求，需要等待结果
        return [self determineResolveHostBlocking:request];
    } else {
        // 缓存结果不可用，且是异步请求，不需要等待结果
        [self determineResolvingHostNonBlocking:request];
        return nil;
    }
}

- (void)determineResolvingHostNonBlocking:(HttpdnsRequest *)request {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_asyncResolveHostQueue, ^{
        HttpDnsLocker *locker = [HttpDnsLocker sharedInstance];
        __strong typeof(weakSelf) strongSelf = weakSelf;
        @try {
            [locker lock:request.cacheKey queryType:request.queryIpType];
            HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
            [strongSelf executeRequest:request retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex error:nil];
        } @catch (NSException *exception) {
            HttpdnsLogDebug("determineResolvingHostNonBlocking exception: %@", exception);
        } @finally {
            [locker unlock:request.cacheKey queryType:request.queryIpType];
        }
    });
}

- (HttpdnsHostObject *)determineResolveHostBlocking:(HttpdnsRequest *)request {
    HttpdnsHostObject *result = nil;
    HttpDnsLocker *locker = [HttpDnsLocker sharedInstance];
    @try {
        [locker lock:request.cacheKey queryType:request.queryIpType];
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        result = [self executeRequest:request retryCount:0 activatedServerIPIndex:scheduleCenter.activatedServerIPIndex error:nil];
    } @catch (NSException *exception) {
        HttpdnsLogDebug("determineResolveHostBlocking exception: %@", exception);
    } @finally {
        [locker unlock:request.cacheKey queryType:request.queryIpType];
    }
    return result;
}

- (HostObjectExamingResult)examineHttpdnsHostObject:(HttpdnsHostObject *)hostObject underQueryType:(HttpdnsQueryIPType)queryType {
    if (!hostObject) {
        return (HostObjectExamingResult){NO, YES};
    }

    if ([hostObject isIpEmptyUnderQueryIpType:queryType]) {
        return (HostObjectExamingResult){NO, YES};
    }

    if ([hostObject isRegionNotMatch:[self customRegion] underQueryIpType:queryType]) {
        return (HostObjectExamingResult){NO, YES};
    }

    if ([hostObject isExpiredUnderQueryIpType:queryType]) {
        if (_isExpiredIPEnabled || [hostObject isLoadFromDB]) {
            // 只有允许过期缓存，和开启持久化缓存的第一次获取，才不需要等待结果
            HttpdnsLogDebug("The ips is expired, but we accept it, host: %@, queryType: %ld", hostObject.hostName, queryType);
            return (HostObjectExamingResult){YES, YES};
        }

        // 只要过期了就肯定需要请求
        return (HostObjectExamingResult){NO, YES};
    }

    return (HostObjectExamingResult){YES, NO};
}

- (HttpdnsHostObject *)executeRequest:(HttpdnsRequest *)request
                           retryCount:(int)hasRetryedCount
               activatedServerIPIndex:(NSInteger)activatedServerIPIndex
                                error:(NSError *)error {
    NSString *host = request.host;
    NSString *cacheKey = request.cacheKey;
    HttpdnsQueryIPType queryIPType = request.queryIpType;

    if (hasRetryedCount > HTTPDNS_MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogDebug("Internal request retry count exceed limit, host: %@", host);
        [self canNotResolveHost:host error:error isRetry:YES activatedServerIPIndex:activatedServerIPIndex];
        return nil;
    }

    if ([self isDisableToServer]) {
        return nil;
    }

    HttpdnsLogDebug("Internal request starts, host: %@, request: %@", host, request);

    error = nil;
    __block HttpdnsHostObject *result = [[HttpdnsHostResolver new] lookupHostFromServer:request
                                                                     error:&error
                                                    activatedServerIPIndex:activatedServerIPIndex];
    if (error) {
        HttpdnsLogDebug("Internal request error, host: %@, error: %@", host, error);

        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        NSInteger newActivatedServerIPIndex = [scheduleCenter nextServerIPIndexFromIPIndex:activatedServerIPIndex increase:hasRetryedCount];

        return [self executeRequest:request
                         retryCount:(hasRetryedCount + 1)
             activatedServerIPIndex:newActivatedServerIPIndex
                              error:error];
    }

    dispatch_sync(_memoryCacheSerialQueue, ^{
        HttpdnsLogDebug("Internal request finished, host: %@, cacheKey: %@, result: %@", host, cacheKey, result);
        // merge之后，返回的应当是存储在缓存中的实际对象，而非请求过程中构造出来的对象
        result = [self mergeLookupResultToManager:result host:host cacheKey:cacheKey underQueryIpType:queryIPType];
    });
    return result;
}

- (HttpdnsHostObject *)mergeLookupResultToManager:(HttpdnsHostObject *)result host:host cacheKey:(NSString *)cacheKey underQueryIpType:(HttpdnsQueryIPType)queryIpType {
    if (!result) {
        return nil;
    }

    [self disableHttpDnsServer:NO];

    int64_t TTL = [result getTTL];
    int64_t lastLookupTime = [result getLastLookupTime];
    NSArray<NSString *> *IPStrings = [result getIPStrings];
    NSArray<NSString *> *IP6Strings = [result getIP6Strings];
    NSArray<HttpdnsIpObject *> *IPObjects = [result getIps];
    NSArray<HttpdnsIpObject *> *IP6Objects = [result getIp6s];
    NSDictionary* Extra  = [result getExtra];
    NSString *ipRegion = result.ipRegion;
    NSString *ip6Region = result.ip6Region;

    BOOL hasNoIpv4Record = NO;
    BOOL hasNoIpv6Record = NO;
    if (queryIpType & HttpdnsQueryIPTypeIpv4 && [result getIps].count == 0) {
        hasNoIpv4Record = YES;
    }
    if (queryIpType & HttpdnsQueryIPTypeIpv6 && [result getIp6s].count == 0) {
        hasNoIpv6Record = YES;
    }

    HttpdnsHostObject *cachedHostObject = [HttpdnsUtil safeObjectForKey:cacheKey dict:_hostManagerDict];
    if (cachedHostObject) {
        [cachedHostObject setTTL:TTL];
        [cachedHostObject setLastLookupTime:lastLookupTime];
        [cachedHostObject setIsLoadFromDB:NO];
        [cachedHostObject setHasNoIpv4Record:hasNoIpv4Record];
        [cachedHostObject setHasNoIpv6Record:hasNoIpv6Record];

        if (queryIpType & HttpdnsQueryIPTypeIpv4) {
            [cachedHostObject setIps:IPObjects];
            [cachedHostObject setV4TTL:result.getV4TTL];
            [cachedHostObject setLastIPv4LookupTime:result.lastIPv4LookupTime];
            cachedHostObject.ipRegion = ipRegion;
        }

        if (queryIpType & HttpdnsQueryIPTypeIpv6) {
            [cachedHostObject setIp6s:IP6Objects];
            [cachedHostObject setV6TTL:result.getV6TTL];
            [cachedHostObject setLastIPv6LookupTime:result.lastIPv6LookupTime];
            cachedHostObject.ip6Region = ip6Region;
        }

        if ([HttpdnsUtil isNotEmptyDictionary:result.extra]) {
            [cachedHostObject setExtra:Extra];
        }

        HttpdnsLogDebug("####### Update cached hostObject, cacheKey: %@, host: %@, result: %@", cacheKey, host, result);
    } else {
        cachedHostObject = [[HttpdnsHostObject alloc] init];

        [cachedHostObject setHostName:host];
        [cachedHostObject setLastLookupTime:lastLookupTime];
        [cachedHostObject setTTL:TTL];
        [cachedHostObject setHasNoIpv4Record:hasNoIpv4Record];
        [cachedHostObject setHasNoIpv6Record:hasNoIpv6Record];

        [cachedHostObject setIps:IPObjects];
        [cachedHostObject setV4TTL:result.getV4TTL];
        [cachedHostObject setLastIPv4LookupTime:result.lastIPv4LookupTime];
        cachedHostObject.ipRegion = ipRegion;

        [cachedHostObject setIp6s:IP6Objects];
        [cachedHostObject setV6TTL:result.getV6TTL];
        [cachedHostObject setLastIPv6LookupTime:result.lastIPv6LookupTime];
        cachedHostObject.ip6Region = ip6Region;

        if ([HttpdnsUtil isNotEmptyDictionary:result.extra]) {
            [cachedHostObject setExtra:Extra];
        }

        HttpdnsLogDebug("###### New resolved hostObject, cacheKey: %@, host: %@, result: %@", cacheKey, host, result);
        [HttpdnsUtil safeAddValue:cachedHostObject key:cacheKey toDict:_hostManagerDict];
    }

    if([HttpdnsUtil isNotEmptyDictionary:result.extra]) {
        [self sdnsCacheHostRecordAsyncIfNeededWithHost:cacheKey IPs:IPStrings IP6s:IP6Strings TTL:TTL withExtra:Extra ipRegion:ipRegion ip6Region:ip6Region];
    } else {
        [self cacheHostRecordAsyncIfNeededWithHost:cacheKey IPs:IPStrings IP6s:IP6Strings TTL:TTL ipRegion:ipRegion ip6Region:ip6Region];
    }

    [self aysncUpdateIPRankingWithResult:cachedHostObject forHost:host cacheKey:cacheKey];
    return cachedHostObject;
}

- (void)aysncUpdateIPRankingWithResult:(HttpdnsHostObject *)result forHost:(NSString *)host cacheKey:(NSString *)cacheKey {
    if (!self.IPRankingEnabled) {
        return;
    }

    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSDictionary<NSString *, NSString *> *dataSource = sharedService.IPRankingDataSource;
    if (!dataSource || ![dataSource objectForKey:host]) {
        return;
    }

    dispatch_async(_asyncResolveHostQueue, ^(void) {
        [self syncUpdateIPRankingWithResult:result forHost:host cacheKey:cacheKey];
    });
}

- (void)syncUpdateIPRankingWithResult:(HttpdnsHostObject *)result forHost:(NSString *)host cacheKey:cacheKey {
    NSArray<NSString *> *IPStrings = [result getIPStrings];
    NSArray *sortedIps = [[HttpdnsTCPSpeedTester new] ipRankingWithIPs:IPStrings host:host];
    [self updateHostManagerDictWithIPs:sortedIps host:host cacheKey:cacheKey];
}

- (void)updateHostManagerDictWithIPs:(NSArray *)IPs host:(NSString *)host cacheKey:cacheKey {
    HttpdnsHostObject *hostObject = [HttpdnsUtil safeObjectForKey:cacheKey dict:_hostManagerDict];
    if (!hostObject) {
        return;
    }
    if (![HttpdnsUtil isNotEmptyArray:IPs] || ![HttpdnsUtil isNotEmptyString:host]) {
        return;
    }
    @synchronized(self) {
        //FIXME:
        NSMutableArray *ipArray = [[NSMutableArray alloc] init];
        for (NSString *ip in IPs) {
            if (![HttpdnsUtil isNotEmptyString:ip]) {
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
        [HttpdnsUtil safeAddValue:hostObject key:cacheKey toDict:_hostManagerDict];
    }
}

/*!
 * 用户访问引发的嗅探超时的情况，和重试引起的主动嗅探都会访问该方法，但是主动嗅探场景会在 `-[disableHttpDnsServer:]` 里直接返回。
 */
- (void)canNotResolveHost:(NSString *)host error:(NSError *)error isRetry:(BOOL)isRetry activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    NSDictionary *userInfo = error.userInfo;
    //403 ServiceLevelDeny 错误强制更新，不触发disable机制。
    BOOL isServiceLevelDeny = false;
    NSString *errorMessage = [HttpdnsUtil safeObjectForKey:ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY dict:userInfo];
    if ([HttpdnsUtil isNotEmptyString:errorMessage]) {
        isServiceLevelDeny = [errorMessage isEqualToString:ALICLOUD_HTTPDNS_ERROR_SERVICE_LEVEL_DENY];
    }

    if (isServiceLevelDeny) {
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter forceUpdateIpListAsync];
        return;
    }

    BOOL isTimeoutError = [self isTimeoutError:error isHTTPS:HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED];

    if (isRetry && isTimeoutError) {
        [self disableHttpDnsServer:YES];
    }
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
    // 开启允许持久化缓存
    [self setPersistentCacheIpEnabled:enable];
    // 先把当前内存缓存清空
    [self cleanAllExpiredHostRecordsAsyncIfNeeded];
    // 再根据当前网络运营商读取持久化缓存中的历史记录，加载到内存缓存里
    [self asyncReloadCacheFromDbToMemoryByIspCarrier];
}

- (void)setPersistentCacheIpEnabled:(BOOL)enable {
    _persistentCacheIpEnabled = enable;
}

- (BOOL)getPersistentCacheIpEnabled {
    return _persistentCacheIpEnabled;
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

    HttpdnsLogDebug("Network changed, status: %@(%ld), lastNetworkStatus: %ld", statusString, [networkStatus longValue], _lastNetworkStatus);

    if (_lastNetworkStatus == [networkStatus longValue]) {
        return;
    }

    dispatch_async(_asyncResolveHostQueue, ^{
        if (![statusString isEqualToString:@"None"]) {
            NSArray *hostArray = [HttpdnsUtil safeAllKeysFromDict:self->_hostManagerDict];
            [self cleanAllHostMemoryCache];
            [self resetServerDisableDate];

            // 网络发生变化后，上面已经清理内存缓存，现在，要以当前网络运营商为条件去db里找之前是否有缓存，如果是，就复用这个缓存
            // 同步操作，防止网络请求成功，更新后，缓存数据又被重新覆盖
            [self syncReloadCacheFromDbToMemoryByIspCarrier];

            if (self->_isPreResolveAfterNetworkChangedEnabled) {
                HttpdnsLogDebug("Network changed, pre resolve for hosts: %@", hostArray);
                [self addPreResolveHosts:hostArray queryType:HttpdnsQueryIPTypeAuto];
            }
        }
    });
    _lastNetworkStatus = [networkStatus longValue];
}

#pragma mark -
#pragma mark - disable status Setter and Getter Method

- (dispatch_queue_t)cacheQueue {
    if (!_cacheQueue) {
        _cacheQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.cacheDisableStatusQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _cacheQueue;
}

- (void)disableHttpDnsServer:(BOOL)serverDisable {
    dispatch_async(self.cacheQueue, ^{
        if (serverDisable) {
            self->_lastServerDisableDate = [NSDate date];
        } else {
            self->_lastServerDisableDate = nil;
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
    HttpdnsLogDebug("HTTPDNS server disable takes effect, persist success: %@", success ? @"succeeded" : @"failed");
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

- (void)asyncReloadCacheFromDbToMemoryByIspCarrier {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self syncReloadCacheFromDbToMemoryByIspCarrier];
    });
}

- (void)cleanAllHostMemoryCache {
    [HttpdnsUtil safeRemoveAllObjectsFromDict:_hostManagerDict];
}

- (void)cleanCacheWithHostArray:(NSArray<NSString *> *)hostArray {
    if (![HttpdnsUtil isNotEmptyArray:hostArray]) {
        [self cleanAllHostMemoryCache];
    } else {
        for (NSString *host in hostArray) {
            if ([HttpdnsUtil isNotEmptyString:host]) {
                [HttpdnsUtil safeRemoveObjectForKey:host toDict:_hostManagerDict];
            }
        }
    }

    //清空数据库数据
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        //清空数据库数据
        [[HttpdnsHostCacheStore sharedInstance] cleanWithHosts:hostArray];
    });
}

- (void)syncReloadCacheFromDbToMemoryByIspCarrier {
    dispatch_sync(_persistentCacheConcurrentQueue, ^{
        if (!_persistentCacheIpEnabled) {
            return;
        }

        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];

        // 根据运营商名称在db中找一下历史记录
        NSArray<HttpdnsHostRecord *> *hostRecords = [hostCacheStore hostRecordsForCurrentCarrier];

        if (![HttpdnsUtil isNotEmptyArray:hostRecords]) {
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

            // 因为当前持久化缓存为区分cachekey和host(实际是cachekey)
            // 持久化缓存里的host实际上是cachekey
            // 因此这里取出来，如果cachekey和host不一致的情况，这个IP优选会因为查不到datasource而实际不生效
            [self aysncUpdateIPRankingWithResult:hostObject forHost:host cacheKey:host];
        }
    });
}

- (void)cacheHostRecordAsyncIfNeededWithHost:(NSString *)host IPs:(NSArray<NSString *> *)IPs IP6s:(NSArray<NSString *> *)IP6s TTL:(int64_t)TTL ipRegion:(NSString *)ipRegion ip6Region:(NSString *)ip6Region {
    if (!_persistentCacheIpEnabled) {
        return;
    }
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:host IPs:IPs IP6s:IP6s TTL:TTL ipRegion:ipRegion ip6Region:ip6Region];
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
        [hostCacheStore insertHostRecords:@[hostRecord]];
    });
}

- (void)sdnsCacheHostRecordAsyncIfNeededWithHost:(NSString *)host IPs:(NSArray<NSString *> *)IPs IP6s:(NSArray<NSString *> *)IP6s TTL:(int64_t)TTL withExtra:(NSDictionary *)extra ipRegion:(NSString *)ipRegion ip6Region:(NSString *)ip6Region {
    if (!_persistentCacheIpEnabled) {
        return;
    }
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord sdnsHostRecordWithHost:host IPs:IPs IP6s:IP6s TTL:TTL Extra:extra ipRegion:ipRegion ip6Region:ip6Region];
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
        [hostCacheStore insertHostRecords:@[hostRecord]];
    });
}

- (void)cleanAllExpiredHostRecordsAsyncIfNeeded {
    if (!_persistentCacheIpEnabled) {
        return;
    }
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        [[HttpdnsHostCacheStore sharedInstance] cleanAllExpiredHostRecordsSync];
    });
}

#pragma mark -
#pragma mark - 以下函数仅用于测试目的

- (NSString *)showMemoryCache {
    NSString *cacheDes;
    if ([HttpdnsUtil isNotEmptyDictionary:_hostManagerDict]) {
        cacheDes = [NSString stringWithFormat:@"%@", _hostManagerDict];
    }
    return cacheDes;
}

+ (void)setZeroSnifferTimeInterval {
    ALICLOUD_HTTPDNS_ABLE_TO_SNIFFER_AFTER_SERVER_DISABLE_INTERVAL = 0;
}

@end
