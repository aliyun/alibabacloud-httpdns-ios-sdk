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

#import "HttpdnsRequestManager.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsRemoteResolver.h"
#import "HttpdnsLocalResolver.h"
#import "HttpdnsInternalConstant.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsReachability.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsUtil.h"
#import "HttpDnsLocker.h"
#import "HttpdnsRequest_Internal.h"
#import "HttpdnsHostObjectInMemoryCache.h"
#import "HttpdnsIPQualityDetector.h"
#import "HttpdnsIpStackDetector.h"
#import "HttpdnsDB.h"


NSString *const ALICLOUD_HTTPDNS_VALID_SERVER_CERTIFICATE_IP = @"203.107.1.1";

static dispatch_queue_t _persistentCacheConcurrentQueue = NULL;
static dispatch_queue_t _asyncResolveHostQueue = NULL;

typedef struct {
    BOOL isResultUsable;
    BOOL isResolvingRequired;
} HostObjectExamingResult;

@interface HttpdnsRequestManager()

@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, assign, readwrite) NSInteger accountId;
@property (nonatomic, weak) HttpDnsService *ownerService;

@property (atomic, setter=setPersistentCacheIpEnabled:, assign) BOOL persistentCacheIpEnabled;
@property (atomic, setter=setDegradeToLocalDNSEnabled:, assign) BOOL degradeToLocalDNSEnabled;

@property (atomic, assign) NSTimeInterval lastUpdateTimestamp;
@property (atomic, assign) HttpdnsNetworkStatus lastNetworkStatus;

@end

@implementation HttpdnsRequestManager {
    BOOL _isExpiredIPEnabled;
    BOOL _isPreResolveAfterNetworkChangedEnabled;
    HttpdnsHostObjectInMemoryCache *_hostObjectInMemoryCache;
    HttpdnsDB *_httpdnsDB;
}

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _persistentCacheConcurrentQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.persistentCacheOperationQueue", DISPATCH_QUEUE_CONCURRENT);
        _asyncResolveHostQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.asyncResolveHostQueue", DISPATCH_QUEUE_CONCURRENT);
    });
}

- (instancetype)initWithAccountId:(NSInteger)accountId ownerService:(HttpDnsService *)service {
    if (self = [super init]) {
        _accountId = accountId;
        _ownerService = service;

        HttpdnsReachability *reachability = [HttpdnsReachability sharedInstance];
        _isExpiredIPEnabled = NO;
        _isPreResolveAfterNetworkChangedEnabled = NO;
        _hostObjectInMemoryCache = [[HttpdnsHostObjectInMemoryCache alloc] init];
        _httpdnsDB = [[HttpdnsDB alloc] initWithAccountId:accountId];
        [[HttpdnsIpStackDetector sharedInstance] redetectIpStack];

        _lastNetworkStatus = reachability.currentReachabilityStatus;
        _lastUpdateTimestamp = [NSDate date].timeIntervalSince1970;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleReachabilityNotification:)
                                                     name:kHttpdnsReachabilityChangedNotification
                                                   object:reachability];
        [reachability startNotifier];
    }
    return self;
}

- (void)setExpiredIPEnabled:(BOOL)enable {
    _isExpiredIPEnabled = enable;
}

- (void)setCachedIPEnabled:(BOOL)enable discardRecordsHasExpiredFor:(NSTimeInterval)duration {
    // 开启允许持久化缓存
    [self setPersistentCacheIpEnabled:enable];

    if (enable) {
        dispatch_async(_persistentCacheConcurrentQueue, ^{
            // 先清理过期时间超过阈值的缓存结果
            [self->_httpdnsDB cleanRecordAlreadExpiredAt:[[NSDate date] timeIntervalSince1970] - duration];

            // 再读取持久化缓存中的历史记录，加载到内存缓存里
            [self loadCacheFromDbToMemory];
        });
    }
}

- (void)setPreResolveAfterNetworkChanged:(BOOL)enable {
    _isPreResolveAfterNetworkChangedEnabled = enable;
}

- (void)preResolveHosts:(NSArray *)hosts queryType:(HttpdnsQueryIPType)queryType {
    if (![HttpdnsUtil isNotEmptyArray:hosts]) {
        return;
    }

    NSString *combinedHostString = [hosts componentsJoinedByString:@","];

    __weak typeof(self) weakSelf = self;
    dispatch_async(_asyncResolveHostQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if ([strongSelf isHostsNumberLimitReached]) {
            return;
        }

        HttpdnsLogDebug("Pre resolve host by async lookup, hosts: %@", combinedHostString);

        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:combinedHostString queryIpType:queryType];
        request.accountId = strongSelf.accountId;
        [request becomeNonBlockingRequest];
        [strongSelf executePreResolveRequest:request retryCount:0];
    });
}

#pragma mark - core method for all public query API
- (HttpdnsHostObject *)resolveHost:(HttpdnsRequest *)request {
    HttpdnsLogDebug("resolveHost, request: %@", request);

    NSString *host = request.host;
    NSString *cacheKey = request.cacheKey;

    if (request.accountId == 0 || request.accountId != self.accountId) {
        request.accountId = self.accountId;
    }

    if ([HttpdnsUtil isEmptyString:host]) {
        return nil;
    }

    HttpdnsHostObject *result = [_hostObjectInMemoryCache getHostObjectByCacheKey:cacheKey createIfNotExists:^id _Nonnull {
        HttpdnsLogDebug("No cache for cacheKey: %@", cacheKey);
        HttpdnsHostObject *newObject = [HttpdnsHostObject new];
        newObject.hostName = host;
        newObject.v4Ips = @[];
        newObject.v6Ips = @[];
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

            result = [self->_hostObjectInMemoryCache getHostObjectByCacheKey:request.cacheKey];
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
            // 只有开启了允许过期缓存，和开启持久化缓存情况下启动后加载到内存中的缓存，才可以直接复用过期结果
            HttpdnsLogDebug("The ips is expired, but we accept it, host: %@, queryType: %ld, expiredIpEnabled: %d, isLoadFromDB: %d",
                            hostObject.hostName, queryType, _isExpiredIPEnabled, [hostObject isLoadFromDB]);
            // 复用过期结果，同时也需要发起新的解析请求
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
    HttpdnsHostObject *result = nil;

    BOOL isDegradationResult = NO;

    if (hasRetryedCount <= HTTPDNS_MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogDebug("Internal request starts, host: %@, request: %@", host, request);

        NSError *error = nil;
        NSArray<HttpdnsHostObject *> *resultArray = [[HttpdnsRemoteResolver new] resolve:request error:&error];

        if (error) {
            HttpdnsLogDebug("Internal request error, host: %@, error: %@", host, error);

            HttpdnsScheduleCenter *scheduleCenter = self.ownerService.scheduleCenter;
            [scheduleCenter rotateServiceServerHost];

            // 确保一定的重试间隔
            hasRetryedCount++;
            [NSThread sleepForTimeInterval:hasRetryedCount * 0.25];

            return [self executeRequest:request retryCount:hasRetryedCount];
        }

        if ([HttpdnsUtil isEmptyArray:resultArray]) {
            HttpdnsLogDebug("Internal request get empty result array, host: %@", host);
            return nil;
        }

        // 这个路径里，host只会有一个，所以直接取第一个处理就行
        result = resultArray.firstObject;
    } else {
        if (!self.degradeToLocalDNSEnabled) {
            HttpdnsLogDebug("Internal remote request retry count exceed limit, host: %@", host);
            return nil;
        }

        result = [[HttpdnsLocalResolver new] resolve:request];
        if (!result) {
            HttpdnsLogDebug("Fallback to local dns resolver, but still get no result, host: %@", host);
            return nil;
        }

        isDegradationResult = YES;
    }

    HttpdnsLogDebug("Internal request finished, host: %@, cacheKey: %@, isDegradationResult: %d, result: %@ ",
                    host, cacheKey, isDegradationResult, result);

    // merge之后，返回的应当是存储在缓存中的实际对象，而非请求过程中构造出来的对象
    HttpdnsHostObject *lookupResult = [self mergeLookupResultToManager:result host:host cacheKey:cacheKey underQueryIpType:queryIPType];
    // 返回一个快照，避免进行中的一些缓存调整影响返回去的结果
    return [lookupResult copy];
}

- (void)executePreResolveRequest:(HttpdnsRequest *)request retryCount:(int)hasRetryedCount {
    NSString *host = request.host;
    HttpdnsQueryIPType queryIPType = request.queryIpType;

    BOOL isDegradationResult = NO;

    if (hasRetryedCount > HTTPDNS_MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogDebug("PreResolve remote request retry count exceed limit, host: %@", host);
        return;
    }

    HttpdnsLogDebug("PreResolve request starts, host: %@, request: %@", host, request);

    NSError *error = nil;
    NSArray<HttpdnsHostObject *> *resultArray = [[HttpdnsRemoteResolver new] resolve:request error:&error];

    if (error) {
        HttpdnsLogDebug("PreResolve request error, host: %@, error: %@", host, error);

        HttpdnsScheduleCenter *scheduleCenter = self.ownerService.scheduleCenter;
        [scheduleCenter rotateServiceServerHost];

        // 确保一定的重试间隔
        hasRetryedCount++;
        [NSThread sleepForTimeInterval:hasRetryedCount * 0.25];

        [self executeRequest:request retryCount:hasRetryedCount];

        return;
    }

    if ([HttpdnsUtil isEmptyArray:resultArray]) {
        HttpdnsLogDebug("PreResolve request get empty result array, host: %@", host);
        return;
    }

    HttpdnsLogDebug("PreResolve request finished, host: %@, isDegradationResult: %d, result: %@ ",
                    host, isDegradationResult, resultArray);

    for (HttpdnsHostObject *result in resultArray) {
        // merge之后，返回的应当是存储在缓存中的实际对象，而非请求过程中构造出来的对象
        // 预解析不支持SDNS，所以cacheKey只能是单独的每一个hostName
        [self mergeLookupResultToManager:result host:result.hostName cacheKey:result.hostName underQueryIpType:queryIPType];
    }
}

- (HttpdnsHostObject *)mergeLookupResultToManager:(HttpdnsHostObject *)result host:host cacheKey:(NSString *)cacheKey underQueryIpType:(HttpdnsQueryIPType)queryIpType {
    if (!result) {
        return nil;
    }

    NSArray<HttpdnsIpObject *> *v4IpObjects = [result getV4Ips];
    NSArray<HttpdnsIpObject *> *v6IpObjects = [result getV6Ips];
    NSString* extra = [result getExtra];

    BOOL hasNoIpv4Record = NO;
    BOOL hasNoIpv6Record = NO;
    if (queryIpType & HttpdnsQueryIPTypeIpv4 && [HttpdnsUtil isEmptyArray:v4IpObjects]) {
        hasNoIpv4Record = YES;
    }
    if (queryIpType & HttpdnsQueryIPTypeIpv6 && [HttpdnsUtil isEmptyArray:v6IpObjects]) {
        hasNoIpv6Record = YES;
    }

    HttpdnsHostObject *cachedHostObject = [_hostObjectInMemoryCache getHostObjectByCacheKey:cacheKey];
    if (!cachedHostObject) {
        HttpdnsLogDebug("Create new hostObject for cache, cacheKey: %@, host: %@", cacheKey, host);
        cachedHostObject = [[HttpdnsHostObject alloc] init];
    }

    [cachedHostObject setCacheKey:cacheKey];
    [cachedHostObject setClientIp:result.clientIp];

    [cachedHostObject setHostName:host];
    [cachedHostObject setIsLoadFromDB:NO];
    [cachedHostObject setHasNoIpv4Record:hasNoIpv4Record];
    [cachedHostObject setHasNoIpv6Record:hasNoIpv6Record];

    if ([HttpdnsUtil isNotEmptyArray:v4IpObjects]) {
        [cachedHostObject setV4Ips:v4IpObjects];
        [cachedHostObject setV4TTL:result.getV4TTL];
        [cachedHostObject setLastIPv4LookupTime:result.lastIPv4LookupTime];
    }

    if ([HttpdnsUtil isNotEmptyArray:v6IpObjects]) {
        [cachedHostObject setV6Ips:v6IpObjects];
        [cachedHostObject setV6TTL:result.getV6TTL];
        [cachedHostObject setLastIPv6LookupTime:result.lastIPv6LookupTime];
    }

    if ([HttpdnsUtil isNotEmptyString:extra]) {
        [cachedHostObject setExtra:extra];
    }

    HttpdnsLogDebug("Updated hostObject to cached, cacheKey: %@, host: %@", cacheKey, host);

    // 由于从缓存中读取到的是拷贝出来的新对象，字段赋值不会影响缓存中的值对象，因此这里无论如何都要放回缓存
    [_hostObjectInMemoryCache setHostObject:cachedHostObject forCacheKey:cacheKey];

    [self persistToDB:cacheKey hostObject:cachedHostObject];

    NSArray *ipv4StrArray = [cachedHostObject getV4IpStrings];
    if ([HttpdnsUtil isNotEmptyArray:ipv4StrArray]) {
        [self initiateQualityDetectionForIP:ipv4StrArray forHost:host cacheKey:cacheKey];
    }

    NSArray *ipv6StrArray = [cachedHostObject getV6IpStrings];
    if ([HttpdnsUtil isNotEmptyArray:ipv6StrArray]) {
        [self initiateQualityDetectionForIP:ipv6StrArray forHost:host cacheKey:cacheKey];
    }
    return cachedHostObject;
}

- (void)initiateQualityDetectionForIP:(NSArray *)ipArray forHost:(NSString *)host cacheKey:(NSString *)cacheKey {
    HttpDnsService *service = self.ownerService ?: [HttpDnsService sharedInstance];
    NSDictionary<NSString *, NSNumber *> *dataSource = [service getIPRankingDatasource];
    if (!dataSource || ![dataSource objectForKey:host]) {
        return;
    }
    NSNumber *port = [dataSource objectForKey:host];
    for (NSString *ip in ipArray) {
        [[HttpdnsIPQualityDetector sharedInstance] scheduleIPQualityDetection:cacheKey
                                                                           ip:ip
                                                                         port:port
                                                                     callback:^(NSString * _Nonnull cacheKey, NSString * _Nonnull ip, NSInteger costTime) {
            [self->_hostObjectInMemoryCache updateQualityForCacheKey:cacheKey forIp:ip withConnectedRT:costTime];
        }];
    }
}

- (BOOL)isHostsNumberLimitReached {
    if ([_hostObjectInMemoryCache count] >= HTTPDNS_MAX_MANAGE_HOST_NUM) {
        HttpdnsLogDebug("Can't handle more than %d hosts due to the software configuration.", HTTPDNS_MAX_MANAGE_HOST_NUM);
        return YES;
    }
    return NO;
}

- (void)handleReachabilityNotification:(NSNotification *)notification {
    [self networkChanged];
}

- (void)networkChanged {
    HttpdnsNetworkStatus currentStatus = [[HttpdnsReachability sharedInstance] currentReachabilityStatus];
    NSString *currentStatusString = [[HttpdnsReachability sharedInstance] currentReachabilityString];

    // 重新检测协议栈代价小，所以只要网络切换就发起检测
    // 但考虑到网络切换后不稳定，还是延迟1秒才发起
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
        [[HttpdnsIpStackDetector sharedInstance] redetectIpStack];
    });

    NSTimeInterval currentTimestamp = [NSDate date].timeIntervalSince1970;
    BOOL statusChanged = (_lastNetworkStatus != currentStatus);

    // 仅在以下情况下响应网络变化去尝试更新缓存:
    // - 距离上次处理事件至少过去了较长时间，或
    // - 网络状态发生变化且至少过去了较短时间
    NSTimeInterval elapsedTime = currentTimestamp - _lastUpdateTimestamp;
    if (elapsedTime >= 5 || (statusChanged && elapsedTime >= 1)) {
        HttpdnsLogDebug("Processing network change: oldStatus: %ld, newStatus: %ld(%@), elapsedTime=%.2f seconds",
                        _lastNetworkStatus, currentStatus, currentStatusString, elapsedTime);

        // 更新调度
        // 网络在切换过程中可能不稳定，所以发送请求前等待2秒
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
            HttpdnsScheduleCenter *scheduleCenter = self.ownerService.scheduleCenter;
            [scheduleCenter asyncUpdateRegionScheduleConfig];
        });

        NSArray *hostArray = [_hostObjectInMemoryCache allCacheKeys];

        // 预解析
        // 网络在切换过程中可能不稳定，所以在清理缓存和发送请求前等待3秒
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
            [self->_hostObjectInMemoryCache removeAllHostObjects];

            if (self->_isPreResolveAfterNetworkChangedEnabled) {
                HttpdnsLogDebug("Network changed, pre resolve for hosts: %@", hostArray);
                [self preResolveHosts:hostArray queryType:HttpdnsQueryIPTypeAuto];
            }
        });

        // 更新时间戳和状态
        _lastNetworkStatus = currentStatus;
        _lastUpdateTimestamp = currentTimestamp;
    } else {
        HttpdnsLogDebug("Ignoring network change event: oldStatus: %ld, newStatus: %ld(%@), elapsedTime=%.2f seconds",
                        _lastNetworkStatus, currentStatus, currentStatusString, elapsedTime);
    }
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

- (void)loadCacheFromDbToMemory {
    NSArray<HttpdnsHostRecord *> *hostRecords = [self->_httpdnsDB getAllRecords];

    if ([HttpdnsUtil isEmptyArray:hostRecords]) {
        return;
    }

    for (HttpdnsHostRecord *hostRecord in hostRecords) {
        NSString *hostName = hostRecord.hostName;
        NSString *cacheKey = hostRecord.cacheKey;

        HttpdnsHostObject *hostObject = [HttpdnsHostObject fromDBRecord:hostRecord];

        // 从持久层加载到内存的缓存，需要做个标记，App启动后从缓存使用结果时，根据标记做特殊处理
        [hostObject setIsLoadFromDB:YES];

        [self->_hostObjectInMemoryCache setHostObject:hostObject forCacheKey:cacheKey];

        NSArray *v4IpStrArr = [hostObject getV4IpStrings];
        if ([HttpdnsUtil isNotEmptyArray:v4IpStrArr]) {
            [self initiateQualityDetectionForIP:v4IpStrArr forHost:hostName cacheKey:cacheKey];
        }
        NSArray *v6IpStrArr = [hostObject getV6IpStrings];
        if ([HttpdnsUtil isNotEmptyArray:v6IpStrArr]) {
            [self initiateQualityDetectionForIP:v6IpStrArr forHost:hostName cacheKey:cacheKey];
        }
    }
}

- (void)cleanMemoryAndPersistentCacheOfHostArray:(NSArray<NSString *> *)hostArray {
    for (NSString *host in hostArray) {
        if ([HttpdnsUtil isNotEmptyString:host]) {
            [_hostObjectInMemoryCache removeHostObjectByCacheKey:host];
        }
    }

    // 清空数据库数据
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        [self->_httpdnsDB deleteByHostNameArr:hostArray];
    });
}

- (void)cleanMemoryAndPersistentCacheOfAllHosts {
    [_hostObjectInMemoryCache removeAllHostObjects];

    // 清空数据库数据
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        [self->_httpdnsDB deleteAll];
    });
}

- (void)persistToDB:(NSString *)cacheKey hostObject:(HttpdnsHostObject *)hostObject {
    if (!_persistentCacheIpEnabled) {
        return;
    }
    dispatch_async(_persistentCacheConcurrentQueue, ^{
        HttpdnsHostRecord *hostRecord = [hostObject toDBRecord];
        [self->_httpdnsDB createOrUpdate:hostRecord];
    });
}

#pragma mark -
#pragma mark - 以下函数仅用于测试目的

- (NSString *)showMemoryCache {
    NSString *cacheDes;
    cacheDes = [NSString stringWithFormat:@"%@", _hostObjectInMemoryCache];
    return cacheDes;
}

- (void)cleanAllHostMemoryCache {
    [_hostObjectInMemoryCache removeAllHostObjects];
}

- (void)syncLoadCacheFromDbToMemory {
    [self loadCacheFromDbToMemory];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
