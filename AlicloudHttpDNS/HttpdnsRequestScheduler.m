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
#import "HttpdnsIPv6Adapter.h"
#import "HttpDnsLocker.h"
#import "HttpdnsRequest_Internal.h"
#import "HttpdnsThreadSafeDictionary.h"


NSString *const ALICLOUD_HTTPDNS_VALID_SERVER_CERTIFICATE_IP = @"203.107.1.1";

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
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, assign) BOOL persistentCacheIpEnabled;

@end

@implementation HttpdnsRequestScheduler {
    long _lastNetworkStatus;
    BOOL _isExpiredIPEnabled;
    BOOL _isPreResolveAfterNetworkChangedEnabled;
    HttpdnsThreadSafeDictionary *_hostMemCache;
}

+ (void)initialize {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        _persistentCacheConcurrentQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.persistentCacheOperationQueue", DISPATCH_QUEUE_CONCURRENT);
        _asyncResolveHostQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.asyncResolveHostQueue", DISPATCH_QUEUE_CONCURRENT);
    });
}

+ (instancetype)sharedInstance {
    static HttpdnsRequestScheduler *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[HttpdnsRequestScheduler alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _lastNetworkStatus = [HttpdnsReachabilityManager shareInstance].currentNetworkStatus;
        _isExpiredIPEnabled = NO;
        _IPRankingEnabled = NO;
        _isPreResolveAfterNetworkChangedEnabled = NO;
        _hostMemCache = [[HttpdnsThreadSafeDictionary alloc] init];
        [HttpdnsIPv6Adapter getInstance];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(networkChanged:)
                                                     name:ALICLOUD_NETWOEK_STATUS_NOTIFY
                                                   object:nil];
    }
    return self;
}

- (void)addPreResolveHosts:(NSArray *)hosts queryType:(HttpdnsQueryIPType)queryType{
    if (![HttpdnsUtil isNotEmptyArray:hosts]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(_asyncResolveHostQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        for (NSString *hostName in hosts) {
            if ([strongSelf isHostsNumberLimitReached]) {
                break;
            }
            HttpdnsHostObject *hostObject = [strongSelf->_hostMemCache objectForKey:hostName];
            if (!hostObject || [hostObject isExpiredUnderQueryIpType:queryType]) {
                HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:hostName queryIpType:queryType];
                [request setAsNonBlockingRequest];
                [strongSelf resolveHost:request];
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

    HttpdnsHostObject *result = [_hostMemCache getObjectForKey:cacheKey createIfNotExists:^id _Nonnull {
        HttpdnsLogDebug("No cache for cacheKey: %@", cacheKey);
        HttpdnsHostObject *newObject = [HttpdnsHostObject new];
        newObject.hostName = host;
        newObject.ips = @[];
        newObject.ip6s = @[];
        newObject.extra = @{};
        return newObject;
    }];

    HostObjectExamingResult examingResult = [self examineHttpdnsHostObject:result underQueryType:request.queryIpType];
    BOOL isCachedResultUsable = examingResult.isResultUsable;
    BOOL isResolvingRequired = examingResult.isResolvingRequired;

    if (isCachedResultUsable) {
        if (isResolvingRequired) {
            // 缓存结果可用，但是需要请求，因为缓存结果已经过期
            // 这种情况异步去解析就可以了
            [self determineResolvingHostNonBlocking:request];
        }
        // 缓存是以cacheKey为准，这里返回前，要把host替换成用户请求的这个
        result.hostName = host;
        HttpdnsLogDebug("Reuse available cache for cacheKey: %@, result: %@", cacheKey, result);
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
    dispatch_async(_asyncResolveHostQueue, ^{
        HttpDnsLocker *locker = [HttpDnsLocker sharedInstance];
        if ([locker tryLock:request.cacheKey queryType:request.queryIpType]) {
            @try {
                [self executeRequest:request retryCount:0];
            } @catch (NSException *exception) {
                HttpdnsLogDebug("determineResolvingHostNonBlocking host: %@, exception: %@", request.host, exception);
            } @finally {
                [locker unlock:request.cacheKey queryType:request.queryIpType];
            }
        } else {
            HttpdnsLogDebug("determineResolvingHostNonBlocking skipped due to concurrent limitation, host: %@", request.host);
        }
    });
}

- (HttpdnsHostObject *)determineResolveHostBlocking:(HttpdnsRequest *)request {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block HttpdnsHostObject *result = nil;
    dispatch_async(_asyncResolveHostQueue, ^{
        HttpDnsLocker *locker = [HttpDnsLocker sharedInstance];
        @try {
            [locker lock:request.cacheKey queryType:request.queryIpType];

            result = [self->_hostMemCache objectForKey:request.cacheKey];
            if (result && ![result isExpiredUnderQueryIpType:request.queryIpType]) {
                // 存在且未过期，意味着其他线程已经解析到了新的结果
                return;
            }

            result = [self executeRequest:request retryCount:0];
        } @catch (NSException *exception) {
            HttpdnsLogDebug("determineResolveHostBlocking host: %@, exception: %@", request.host, exception);
        } @finally {
            [locker unlock:request.cacheKey queryType:request.queryIpType];
            dispatch_semaphore_signal(semaphore);
        }
    });
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(request.resolveTimeoutInSecond * NSEC_PER_SEC)));
    return result;
}

- (HostObjectExamingResult)examineHttpdnsHostObject:(HttpdnsHostObject *)hostObject underQueryType:(HttpdnsQueryIPType)queryType {
    if (!hostObject) {
        return (HostObjectExamingResult){NO, YES};
    }

    if ([hostObject isIpEmptyUnderQueryIpType:queryType]) {
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

- (HttpdnsHostObject *)executeRequest:(HttpdnsRequest *)request retryCount:(int)hasRetryedCount {
    NSString *host = request.host;
    NSString *cacheKey = request.cacheKey;
    HttpdnsQueryIPType queryIPType = request.queryIpType;

    if (hasRetryedCount > HTTPDNS_MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogDebug("Internal request retry count exceed limit, host: %@", host);
        return nil;
    }

    HttpdnsLogDebug("Internal request starts, host: %@, request: %@", host, request);

    NSError *error = nil;

    __block HttpdnsHostObject *result = [[HttpdnsHostResolver new] lookupHostFromServer:request error:&error];

    if (error) {
        HttpdnsLogDebug("Internal request error, host: %@, error: %@", host, error);

        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter moveToNextServiceServerHost];

        // 确保一定的重试间隔
        hasRetryedCount++;
        [NSThread sleepForTimeInterval:hasRetryedCount * 0.25];

        return [self executeRequest:request retryCount:hasRetryedCount];
    }

    HttpdnsLogDebug("Internal request finished, host: %@, cacheKey: %@, result: %@", host, cacheKey, result);
    // merge之后，返回的应当是存储在缓存中的实际对象，而非请求过程中构造出来的对象
    HttpdnsHostObject *lookupResult = [self mergeLookupResultToManager:result host:host cacheKey:cacheKey underQueryIpType:queryIPType];
    // 返回一个快照，避免进行中的一些缓存调整影响返回去的结果
    return [lookupResult copy];
}

- (HttpdnsHostObject *)mergeLookupResultToManager:(HttpdnsHostObject *)result host:host cacheKey:(NSString *)cacheKey underQueryIpType:(HttpdnsQueryIPType)queryIpType {
    if (!result) {
        return nil;
    }

    int64_t ttl = [result getTTL];
    int64_t lastLookupTime = [result getLastLookupTime];
    NSArray<NSString *> *ip4Strings = [result getIPStrings];
    NSArray<NSString *> *ip6Strings = [result getIP6Strings];
    NSArray<HttpdnsIpObject *> *ip4Objects = [result getIps];
    NSArray<HttpdnsIpObject *> *ip6Objects = [result getIp6s];
    NSDictionary* extra = [result getExtra];

    BOOL hasNoIpv4Record = NO;
    BOOL hasNoIpv6Record = NO;
    if (queryIpType & HttpdnsQueryIPTypeIpv4 && [HttpdnsUtil isEmptyArray:ip4Objects]) {
        hasNoIpv4Record = YES;
    }
    if (queryIpType & HttpdnsQueryIPTypeIpv6 && [HttpdnsUtil isEmptyArray:ip6Objects]) {
        hasNoIpv6Record = YES;
    }

    HttpdnsHostObject *cachedHostObject = [_hostMemCache objectForKey:cacheKey];
    if (!cachedHostObject) {
        HttpdnsLogDebug("Create new hostObject for cache, cacheKey: %@, host: %@", cacheKey, host);
        cachedHostObject = [[HttpdnsHostObject alloc] init];
    }

    [cachedHostObject setHostName:host];
    [cachedHostObject setTTL:ttl];
    [cachedHostObject setLastLookupTime:lastLookupTime];
    [cachedHostObject setIsLoadFromDB:NO];
    [cachedHostObject setHasNoIpv4Record:hasNoIpv4Record];
    [cachedHostObject setHasNoIpv6Record:hasNoIpv6Record];

    if ([HttpdnsUtil isNotEmptyArray:ip4Objects]) {
        [cachedHostObject setIps:ip4Objects];
        [cachedHostObject setV4TTL:result.getV4TTL];
        [cachedHostObject setLastIPv4LookupTime:result.lastIPv4LookupTime];
    }

    if ([HttpdnsUtil isNotEmptyArray:ip6Objects]) {
        [cachedHostObject setIp6s:ip6Objects];
        [cachedHostObject setV6TTL:result.getV6TTL];
        [cachedHostObject setLastIPv6LookupTime:result.lastIPv6LookupTime];
    }

    if ([HttpdnsUtil isNotEmptyDictionary:extra]) {
        [cachedHostObject setExtra:extra];
    }

    HttpdnsLogDebug("Updated hostObject to cached, cacheKey: %@, host: %@", cacheKey, host);

    NSArray *ipv4StrArray = [cachedHostObject getIPStrings];

    // 由于从缓存中读取到的是拷贝出来的新对象，字段赋值不会影响缓存中的值对象，因此这里无论如何都要放回缓存
    [_hostMemCache setObject:cachedHostObject forKey:cacheKey];

    if([HttpdnsUtil isNotEmptyDictionary:extra]) {
        [self sdnsCacheHostRecordAsyncIfNeededWithHost:cacheKey IPs:ip4Strings IP6s:ip6Strings TTL:ttl withExtra:extra];
    } else {
        [self cacheHostRecordAsyncIfNeededWithHost:cacheKey IPs:ip4Strings IP6s:ip6Strings TTL:ttl];
    }

    // 目前只处理ipv4地址
    [self asyncUpdateIPRankingWithIpv4StrArray:ipv4StrArray forHost:host cacheKey:cacheKey];
    return cachedHostObject;
}

- (void)asyncUpdateIPRankingWithIpv4StrArray:(NSArray *)ipv4StrArray forHost:(NSString *)host cacheKey:(NSString *)cacheKey {
    if (!self.IPRankingEnabled) {
        return;
    }

    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSDictionary<NSString *, NSString *> *dataSource = sharedService.IPRankingDataSource;
    if (!dataSource || ![dataSource objectForKey:host]) {
        return;
    }

    dispatch_async(_asyncResolveHostQueue, ^(void) {
        [self syncUpdateIPRankingWithIpv4StrArray:ipv4StrArray forHost:host cacheKey:cacheKey];
    });
}

- (void)syncUpdateIPRankingWithIpv4StrArray:(NSArray *)ipv4StrArray forHost:(NSString *)host cacheKey:cacheKey {
    NSArray *sortedIps = [[HttpdnsTCPSpeedTester new] ipRankingWithIPs:ipv4StrArray host:host];

    if ([HttpdnsUtil isEmptyArray:sortedIps]) {
        return;
    }

    [self updateHostManagerDictWithIPs:sortedIps host:host cacheKey:cacheKey];
}

- (void)updateHostManagerDictWithIPs:(NSArray *)sortedIps host:(NSString *)host cacheKey:cacheKey {
    HttpdnsHostObject *hostObject = [_hostMemCache objectForKey:cacheKey];
    if (!hostObject) {
        return;
    }

    @synchronized(self) {
        NSMutableArray *ipArray = [[NSMutableArray alloc] init];
        for (NSString *ip in sortedIps) {
            if ([HttpdnsUtil isEmptyString:ip]) {
                continue;
            }

            HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
            [ipObject setIp:ip];
            [ipArray addObject:ipObject];
        }
        [hostObject setIps:ipArray];

        [_hostMemCache setObject:hostObject forKey:cacheKey];
    }
}

- (BOOL)isHostsNumberLimitReached {
    if ([_hostMemCache count] >= HTTPDNS_MAX_MANAGE_HOST_NUM) {
        HttpdnsLogDebug("Can't handle more than %d hosts due to the software configuration.", HTTPDNS_MAX_MANAGE_HOST_NUM);
        return YES;
    }
    return NO;
}

- (void)setExpiredIPEnabled:(BOOL)enable {
    _isExpiredIPEnabled = enable;
}

- (void)setCachedIPEnabled:(BOOL)enable discardRecordsHasExpiredFor:(NSTimeInterval)duration {
    // 开启允许持久化缓存
    [self setPersistentCacheIpEnabled:enable];

    if (enable) {
        // 先清理过期时间超过阈值的缓存结果
        [self cleanHostRecordsAlreadyExpiredAt:[[NSDate date] timeIntervalSince1970] - duration];

        // 再根据当前网络运营商读取持久化缓存中的历史记录，加载到内存缓存里
        [self asyncReloadCacheFromDbToMemoryByIspCarrier];
    }
}

- (void)setPersistentCacheIpEnabled:(BOOL)enable {
    _persistentCacheIpEnabled = enable;
}

- (BOOL)getPersistentCacheIpEnabled {
    return _persistentCacheIpEnabled;
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
            HttpdnsLogDebug("Network changed, currentNetworkStatus: None, lastNetworkStatus: %ld", _lastNetworkStatus);
            return;
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

    HttpdnsLogDebug("Network changed, currentNetworkStatus: %ld(%@), lastNetworkStatus: %ld", [networkStatus longValue], statusString, _lastNetworkStatus);

    if (_lastNetworkStatus == [networkStatus longValue]) {
        return;
    }
    _lastNetworkStatus = [networkStatus longValue];

    NSArray *hostArray = [_hostMemCache allKeys];

    dispatch_async(_asyncResolveHostQueue, ^{
        [self cleanAllHostMemoryCache];

        // 网络发生变化后，上面已经清理内存缓存，现在，要以当前网络运营商为条件去db里找之前是否有缓存，如果是，就复用这个缓存
        // 同步操作，防止网络请求成功，更新后，缓存数据又被重新覆盖
        [self syncReloadCacheFromDbToMemoryByIspCarrier];
    });

    // 网络切换过程中网络可能不稳定，发出去的请求失败概率高，所以等待一段时间再发出请求
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), _asyncResolveHostQueue, ^{
        // 更新调度列表
        HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
        [scheduleCenter asyncUpdateRegionScheduleConfig];

        if (self->_isPreResolveAfterNetworkChangedEnabled) {
            HttpdnsLogDebug("Network changed, pre resolve for hosts: %@", hostArray);
            [self addPreResolveHosts:hostArray queryType:HttpdnsQueryIPTypeAuto];
        }
    });
}

#pragma mark -
#pragma mark - disable status Setter and Getter Method

- (dispatch_queue_t)cacheQueue {
    if (!_cacheQueue) {
        _cacheQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.cacheDisableStatusQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _cacheQueue;
}

#pragma mark -
#pragma mark - Flag for Disable and Sniffer Method

- (void)asyncReloadCacheFromDbToMemoryByIspCarrier {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self syncReloadCacheFromDbToMemoryByIspCarrier];
    });
}

- (void)cleanAllHostMemoryCache {
    [_hostMemCache removeAllObjects];
}

- (void)cleanMemoryAndPersistentCacheOfHostArray:(NSArray<NSString *> *)hostArray {
    for (NSString *host in hostArray) {
        if ([HttpdnsUtil isNotEmptyString:host]) {
            [_hostMemCache removeObjectForKey:host];
        }
    }

    // 清空数据库数据
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        [[HttpdnsHostCacheStore sharedInstance] cleanDbOfHosts:hostArray];
    });
}

- (void)cleanMemoryAndPersistentCacheOfAllHosts {
    [self cleanAllHostMemoryCache];

    // 清空数据库数据
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        [[HttpdnsHostCacheStore sharedInstance] cleanDbOfAllHosts];
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

            // 从DB缓存中加载到内存里的数据，更新其查询时间为当前，使得它可以有一个TTL的可用期
            [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];

            NSArray *ipv4StrArr = [hostObject getIPStrings];

            [_hostMemCache setObject:hostObject forKey:host];

            // 因为当前持久化缓存为区分cachekey和host(实际是cachekey)
            // 持久化缓存里的host实际上是cachekey
            // 因此这里取出来，如果cachekey和host不一致的情况，这个IP优选会因为查不到datasource而实际不生效
            [self asyncUpdateIPRankingWithIpv4StrArray:ipv4StrArr forHost:host cacheKey:host];
        }
    });
}

- (void)cacheHostRecordAsyncIfNeededWithHost:(NSString *)host IPs:(NSArray<NSString *> *)IPs IP6s:(NSArray<NSString *> *)IP6s TTL:(int64_t)TTL {
    if (!_persistentCacheIpEnabled) {
        return;
    }
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:host IPs:IPs IP6s:IP6s TTL:TTL ipRegion:@"" ip6Region:@""];
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
        [hostCacheStore insertHostRecords:@[hostRecord]];
    });
}

- (void)sdnsCacheHostRecordAsyncIfNeededWithHost:(NSString *)host IPs:(NSArray<NSString *> *)IPs IP6s:(NSArray<NSString *> *)IP6s TTL:(int64_t)TTL withExtra:(NSDictionary *)extra {
    if (!_persistentCacheIpEnabled) {
        return;
    }
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord sdnsHostRecordWithHost:host IPs:IPs IP6s:IP6s TTL:TTL Extra:extra ipRegion:@"" ip6Region:@""];
        HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
        [hostCacheStore insertHostRecords:@[hostRecord]];
    });
}

- (void)cleanHostRecordsAlreadyExpiredAt:(NSTimeInterval)specifiedTime {
    if (!_persistentCacheIpEnabled) {
        return;
    }
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        [[HttpdnsHostCacheStore sharedInstance] cleanHostRecordsAlreadyExpiredAt:specifiedTime];
    });
}

#pragma mark -
#pragma mark - 以下函数仅用于测试目的

- (NSString *)showMemoryCache {
    NSString *cacheDes;
    cacheDes = [NSString stringWithFormat:@"%@", _hostMemCache];
    return cacheDes;
}

@end
