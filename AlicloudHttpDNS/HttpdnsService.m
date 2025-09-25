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
#import "HttpdnsService_Internal.h"
#import "HttpdnsRemoteResolver.h"
#import "HttpdnsInternalConstant.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsRequest_Internal.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsPublicConstant.h"
#import "HttpdnsRegionConfigLoader.h"
#import "HttpdnsIpStackDetector.h"



static dispatch_queue_t asyncTaskConcurrentQueue;
static NSMutableDictionary<NSNumber *, HttpDnsService *> *httpdnsServiceInstances;
static dispatch_queue_t httpdnsServiceInstancesQueue;
static HttpDnsService *httpdnsFirstInitializedInstance;
static HttpDnsService *httpdnsSharedStubInstance;

@interface HttpDnsService ()

@property (nonatomic, assign) NSInteger accountID;
@property (nonatomic, copy) NSString *secretKey;
@property (nonatomic, copy) NSString *aesSecretKey;
@property (nonatomic, assign) BOOL hasConfiguredAccount;

 // 每次访问的签名有效期，SDK内部定死，当前不暴露设置接口，有效期定为10分钟。
@property (nonatomic, assign) NSUInteger authTimeoutInterval;

@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *presetSdnsParamsDict;

// scheduleCenter 已在 HttpdnsService_Internal.h 暴露，避免重复声明

@end

@implementation HttpDnsService

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        asyncTaskConcurrentQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.asyncTask", DISPATCH_QUEUE_CONCURRENT);
        httpdnsServiceInstances = [NSMutableDictionary dictionary];
        httpdnsServiceInstancesQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.serviceRegistry", DISPATCH_QUEUE_SERIAL);
    });
}

#pragma mark -
#pragma mark ---------- singleton


+ (nonnull instancetype)sharedInstance {
    __block HttpDnsService *firstInstance = nil;
    dispatch_sync(httpdnsServiceInstancesQueue, ^{
        firstInstance = httpdnsFirstInitializedInstance;
    });
    if (firstInstance) {
        return firstInstance;
    }

    static dispatch_once_t stubOnceToken;
    dispatch_once(&stubOnceToken, ^{
        httpdnsSharedStubInstance = [[self alloc] init];
    });
    return httpdnsSharedStubInstance;
}

+ (nullable instancetype)getInstanceByAccountId:(NSInteger)accountID {
    __block HttpDnsService *instance = nil;
    dispatch_sync(httpdnsServiceInstancesQueue, ^{
        instance = httpdnsServiceInstances[@(accountID)];
    });
    return instance;
}

+ (NSArray<HttpDnsService *> *)allRegisteredInstances {
    __block NSArray<HttpDnsService *> *instances = nil;
    dispatch_sync(httpdnsServiceInstancesQueue, ^{
        instances = [httpdnsServiceInstances allValues];
    });
    return instances ?: @[];
}

+ (HttpDnsService *)instanceForAccountIDCreatingIfNeeded:(NSInteger)accountID {
    __block HttpDnsService *instance = nil;
    dispatch_sync(httpdnsServiceInstancesQueue, ^{
        instance = httpdnsServiceInstances[@(accountID)];
        if (instance) {
            return;
        }

        if (!httpdnsFirstInitializedInstance) {
            if (httpdnsSharedStubInstance) {
                instance = httpdnsSharedStubInstance;
            } else {
                instance = [[self alloc] init];
                httpdnsSharedStubInstance = instance;
            }
            httpdnsFirstInitializedInstance = instance;
        } else {
            instance = [[self alloc] init];
        }

        httpdnsServiceInstances[@(accountID)] = instance;
    });
    return instance;
}

- (nonnull instancetype)initWithAccountID:(NSInteger)accountID {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    return [self initWithAccountID:accountID secretKey:nil];
#pragma clang diagnostic pop
}

- (nonnull instancetype)initWithAccountID:(NSInteger)accountID secretKey:(NSString *)secretKey {
    return [self initWithAccountID:accountID secretKey:secretKey aesSecretKey:nil];
}

- (nonnull instancetype)initWithAccountID:(NSInteger)accountID secretKey:(NSString *)secretKey aesSecretKey:(NSString *)aesSecretKey {
    HttpDnsService *existing = [HttpDnsService getInstanceByAccountId:accountID];
    if (existing) {
        return existing;
    }

    HttpDnsService *service = [HttpDnsService instanceForAccountIDCreatingIfNeeded:accountID];
    [service configureWithAccountID:accountID secretKey:secretKey aesSecretKey:aesSecretKey];
    return service;
}

- (void)configureWithAccountID:(NSInteger)accountID
                      secretKey:(NSString *)secretKey
                   aesSecretKey:(NSString *)aesSecretKey {
    @synchronized (self) {
        if (self.hasConfiguredAccount) {
            return;
        }

        self.accountID = accountID;
        self.secretKey = [secretKey copy];
        self.aesSecretKey = [aesSecretKey copy];

        self.timeoutInterval = HTTPDNS_DEFAULT_REQUEST_TIMEOUT_INTERVAL;
        self.authTimeoutInterval = HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL;
        self.enableHttpsRequest = NO;
        self.hasAllowedArbitraryLoadsInATS = NO;
        self.enableDegradeToLocalDNS = NO;

        self.requestManager = [[HttpdnsRequestManager alloc] initWithAccountId:accountID ownerService:self];

        NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
        NSString *regionKey = [NSString stringWithFormat:@"%@.%ld", kAlicloudHttpdnsRegionKey, (long)accountID];
        NSString *cachedRegion = [userDefault objectForKey:regionKey];

        HttpdnsScheduleCenter *scheduleCenter = [[HttpdnsScheduleCenter alloc] initWithAccountId:accountID];
        [scheduleCenter initRegion:cachedRegion];
        self.scheduleCenter = scheduleCenter;

        self.hasConfiguredAccount = YES;
    }
}

- (void)attachAccountInfoToRequest:(HttpdnsRequest *)request {
    request.accountId = self.accountID;
}

#pragma mark -
#pragma mark -------------- public

- (void)setAuthCurrentTime:(NSUInteger)authCurrentTime {
    [self setInternalAuthTimeBaseBySpecifyingCurrentTime:authCurrentTime];
}

- (void)setInternalAuthTimeBaseBySpecifyingCurrentTime:(NSTimeInterval)currentTime {
    NSTimeInterval localTime = [[NSDate date] timeIntervalSince1970];
    _authTimeOffset = currentTime - localTime;
}

- (void)setCachedIPEnabled:(BOOL)enable {
    [self setPersistentCacheIPEnabled:enable];
}

- (void)setPersistentCacheIPEnabled:(BOOL)enable {
    [_requestManager setCachedIPEnabled:enable discardRecordsHasExpiredFor:0];
}

- (void)setPersistentCacheIPEnabled:(BOOL)enable discardRecordsHasExpiredFor:(NSTimeInterval)duration {
    if (duration < 0) {
        duration = 0;
    }
    if (duration > SECONDS_OF_ONE_YEAR) {
        duration = SECONDS_OF_ONE_YEAR;
    }
    [_requestManager setCachedIPEnabled:enable discardRecordsHasExpiredFor:duration];
}

- (void)setExpiredIPEnabled:(BOOL)enable {
    [self setReuseExpiredIPEnabled:enable];
}

- (void)setReuseExpiredIPEnabled:(BOOL)enable {
    [_requestManager setExpiredIPEnabled:enable];
}

- (void)setHTTPSRequestEnabled:(BOOL)enable {
    _enableHttpsRequest = enable;
}

- (void)setHasAllowedArbitraryLoadsInATS:(BOOL)hasAllowedArbitraryLoadsInATS {
    _hasAllowedArbitraryLoadsInATS = hasAllowedArbitraryLoadsInATS;
}

- (void)setNetworkingTimeoutInterval:(NSTimeInterval)timeoutInterval {
    _timeoutInterval = timeoutInterval;
}

- (void)setRegion:(NSString *)region {
    if ([HttpdnsUtil isEmptyString:region]) {
        region = ALICLOUD_HTTPDNS_DEFAULT_REGION_KEY;
    }

    if (![[HttpdnsRegionConfigLoader getAvailableRegionList] containsObject:region]) {
        HttpdnsLogDebug("Invalid region: %@, we currently only support these regions: %@", region, [HttpdnsRegionConfigLoader getAvailableRegionList]);
        return;
    }

    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    NSString *regionKey = [NSString stringWithFormat:@"%@.%ld", kAlicloudHttpdnsRegionKey, (long)self.accountID];
    NSString *oldRegion = [userDefault objectForKey:regionKey];
    if (![region isEqualToString:oldRegion]) {
        [userDefault setObject:region forKey:regionKey];

        // 仅清空本实例缓存，调度按账号隔离
        [self cleanHostCache:nil];

        // region变化后仅更新本实例的服务IP
        [self.scheduleCenter resetRegion:region];
    }
}

- (void)setPreResolveHosts:(NSArray *)hosts {
    [self setPreResolveHosts:hosts byIPType:HttpdnsQueryIPTypeBoth];
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

    [self setPreResolveHosts:hosts byIPType:ipQueryType];
}

- (void)setPreResolveHosts:(NSArray *)hosts byIPType:(HttpdnsQueryIPType)ipType {
    // 初始化过程包含了region配置更新流程，region切换会导致缓存清空，立即做预解析可能是没有意义的
    // 这是sdk接口设计的历史问题，目前没有太好办法，这里0.5秒之后再发预解析请求
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), asyncTaskConcurrentQueue, ^{
        [self->_requestManager preResolveHosts:hosts queryType:ipType];
    });
}

- (void)setLogEnabled:(BOOL)enable {
    if (enable) {
        [HttpdnsLog enableLog];
    } else {
        [HttpdnsLog disableLog];
    }
}

- (void)setPreResolveAfterNetworkChanged:(BOOL)enable {
    [_requestManager setPreResolveAfterNetworkChanged:enable];
}

- (void)setIPRankingDatasource:(NSDictionary<NSString *, NSNumber *> *)IPRankingDatasource {
    _IPRankingDataSource = IPRankingDatasource;
}

- (NSDictionary<NSString *, NSNumber *> *)getIPRankingDatasource {
    return [_IPRankingDataSource copy];
}

- (void)setDegradeToLocalDNSEnabled:(BOOL)enable {
    _enableDegradeToLocalDNS = enable;
    [_requestManager setDegradeToLocalDNSEnabled:enable];
}

- (void)enableIPv6:(BOOL)enable {
    [self setIPv6Enabled:enable];
}

- (void)setIPv6Enabled:(BOOL)enable {
    // 默认都支持
}

- (void)enableNetworkInfo:(BOOL)enable {
    // 弃用此接口
}

- (void)setReadNetworkInfoEnabled:(BOOL)enable {
    // 弃用此接口
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

- (nullable HttpdnsResult *)resolveHostSync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType {
    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:queryIpType];
    [self attachAccountInfoToRequest:request];
    return [self resolveHostSync:request];
}

- (nullable HttpdnsResult *)resolveHostSync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *,NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey {
    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:queryIpType sdnsParams:sdnsParams cacheKey:cacheKey];
    [self attachAccountInfoToRequest:request];
    return [self resolveHostSync:request];
}

- (nullable HttpdnsResult *)resolveHostSync:(HttpdnsRequest *)request {
    if ([NSThread isMainThread]) {
        // 主线程做一个防御
        return [self resolveHostSyncNonBlocking:request];
    }

    if (![self validateResolveRequest:request]) {
        return nil;
    }

    if ([self _shouldDegradeHTTPDNS:request.host]) {
        return nil;
    }

    [self refineResolveRequest:request];
    [request becomeBlockingRequest];

    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (!hostObject) {
        return nil;
    }
    return [self constructResultFromHostObject:hostObject underQueryType:request.queryIpType];
}

- (nullable HttpdnsResult *)resolveHostSyncNonBlocking:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType {
    return [self resolveHostSyncNonBlocking:host byIpType:queryIpType withSdnsParams:nil sdnsCacheKey:nil];
}

- (nullable HttpdnsResult *)resolveHostSyncNonBlocking:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *,NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey {
    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:queryIpType sdnsParams:sdnsParams cacheKey:cacheKey];
    [self attachAccountInfoToRequest:request];
    return [self resolveHostSyncNonBlocking:request];
}

- (nullable HttpdnsResult *)resolveHostSyncNonBlocking:(HttpdnsRequest *)request {
    if (![self validateResolveRequest:request]) {
        return nil;
    }

    if ([self _shouldDegradeHTTPDNS:request.host]) {
        return nil;
    }

    [self refineResolveRequest:request];
    [request becomeNonBlockingRequest];

    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (!hostObject) {
        return nil;
    }
    return [self constructResultFromHostObject:hostObject underQueryType:request.queryIpType];
}

- (void)resolveHostAsync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType completionHandler:(void (^)(HttpdnsResult * nullable))handler {
    [self resolveHostAsync:host byIpType:queryIpType withSdnsParams:nil sdnsCacheKey:nil completionHandler:handler];
}

- (void)resolveHostAsync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *,NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey completionHandler:(void (^)(HttpdnsResult * nullable))handler {
    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:queryIpType sdnsParams:sdnsParams cacheKey:cacheKey];
    [self attachAccountInfoToRequest:request];
    [self resolveHostAsync:request completionHandler:handler];
}

- (void)resolveHostAsync:(HttpdnsRequest *)request completionHandler:(void (^)(HttpdnsResult * nullable))handler {
    if (![self validateResolveRequest:request]) {
        dispatch_async(asyncTaskConcurrentQueue, ^{
            handler(nil);
        });
    }

    if ([self _shouldDegradeHTTPDNS:request.host]) {
        dispatch_async(asyncTaskConcurrentQueue, ^{
            handler(nil);
        });
    }

    [self refineResolveRequest:request];

    double enqueueStart = [[NSDate date] timeIntervalSince1970] * 1000;
    dispatch_async(asyncTaskConcurrentQueue, ^{
        double executeStart = [[NSDate date] timeIntervalSince1970] * 1000;
        [request becomeBlockingRequest];
        HttpdnsHostObject *hostObject = [self->_requestManager resolveHost:request];
        double innerEnd = [[NSDate date] timeIntervalSince1970] * 1000;
        HttpdnsLogDebug("resolveHostAsync done, inner cost time from enqueue: %fms, from execute: %fms", (innerEnd - enqueueStart), (innerEnd - executeStart));

        if (!hostObject) {
            handler(nil);
        } else {
            handler([self constructResultFromHostObject:hostObject underQueryType:request.queryIpType]);
        }
    });
}

- (HttpdnsQueryIPType)determineLegitQueryIpType:(HttpdnsQueryIPType)specifiedQueryIpType {
    // 自动选择，需要判断当前网络环境来决定
    if (specifiedQueryIpType == HttpdnsQueryIPTypeAuto) {
        HttpdnsIPStackType stackType = [[HttpdnsIpStackDetector sharedInstance] currentIpStack];
        switch (stackType) {
            // 双栈和ipv6only，两个类型都要请求
            // 虽然判断是ipv6only，但现实中只有实验室才会有这种情况，考虑判断网络协议栈是有误判可能的，权衡之下，还是应该请求ipv4
            // 如果用户是在明确的实验室环境中做测试，他应该直接指定请求type为ipv6
            case kHttpdnsIpDual:
            case kHttpdnsIpv6Only:
                return HttpdnsQueryIPTypeIpv4 | HttpdnsQueryIPTypeIpv6;

            // 只有ipv4only的情况，只请求ipv4
            case kHttpdnsIpv4Only:
            default:
                return HttpdnsQueryIPTypeIpv4;
        }
    }

    // 否则就按指定类型来解析
    return specifiedQueryIpType;
}

- (BOOL)validateResolveRequest:(HttpdnsRequest *)request {
    if (!request.host) {
        HttpdnsLogDebug("validateResolveRequest failed, the host should not be nil.")
        return NO;
    }

    if ([HttpdnsUtil isAnIP:request.host]) {
        HttpdnsLogDebug("validateResolveRequest failed, the host is just an IP.");
        return NO;
    }

    if (![HttpdnsUtil isAHost:request.host]) {
        HttpdnsLogDebug("validateResolveRequest failed, the host is illegal.");
        return NO;
    }

    return YES;
}

- (void)refineResolveRequest:(HttpdnsRequest *)request {
    if (request.accountId == 0) {
        request.accountId = self.accountID;
    }
    HttpdnsQueryIPType clarifiedQueryIpType = [self determineLegitQueryIpType:request.queryIpType];
    request.queryIpType = clarifiedQueryIpType;

    NSDictionary *mergedSdnsParam = [self mergeWithPresetSdnsParams:request.sdnsParams];
    request.sdnsParams = mergedSdnsParam;

    if (!request.cacheKey) {
        // 缓存逻辑是依赖cacheKey工作的，如果没有主动设置cacheKey，它实际上就是host
        request.cacheKey = request.host;
    }

    [request ensureResolveTimeoutInReasonableRange];
}

- (HttpdnsResult *)constructResultFromHostObject:(HttpdnsHostObject *)hostObject underQueryType:(HttpdnsQueryIPType)queryType {
    if (!hostObject) {
        return nil;
    }

    if ([HttpdnsUtil isEmptyArray:[hostObject getV4Ips]] && [HttpdnsUtil isEmptyArray:[hostObject getV6Ips]]) {
        // 这里是为了兼容过去用法的行为，如果完全没有ip信息，可以对齐到过去缓存没有ip或解析不到ip的情况，直接返回nil
        return nil;
    }

    HttpdnsResult *result = [HttpdnsResult new];
    result.host = [hostObject getHostName];

    // 由于结果可能是从缓存中获得，所以还要根据实际协议栈情况再筛选下结果
    if (queryType & HttpdnsQueryIPTypeIpv4) {
        NSArray *ipv4s = [hostObject getV4Ips];
        if ([HttpdnsUtil isNotEmptyArray:ipv4s]) {
            NSMutableArray *ipv4Array = [NSMutableArray array];
            for (HttpdnsIpObject *ipObject in ipv4s) {
                [ipv4Array addObject:[ipObject getIpString]];
            }
            result.ips = [ipv4Array copy];
            result.ttl = hostObject.getV4TTL;
            result.lastUpdatedTimeInterval = hostObject.lastIPv4LookupTime;
        }
    }

    if (queryType & HttpdnsQueryIPTypeIpv6) {
        NSArray *ipv6s = [hostObject getV6Ips];
        if ([HttpdnsUtil isNotEmptyArray:ipv6s]) {
            NSMutableArray *ipv6Array = [NSMutableArray array];
            for (HttpdnsIpObject *ipObject in ipv6s) {
                [ipv6Array addObject:[ipObject getIpString]];
            }
            result.ipv6s = [ipv6Array copy];
            result.v6ttl = hostObject.getV6TTL;
            result.v6LastUpdatedTimeInterval = hostObject.lastIPv6LookupTime;
        }
    }

    return result;
}

- (HttpdnsResult *)constructResultFromIp:(NSString *)ip underQueryType:(HttpdnsQueryIPType)queryType {
    HttpdnsResult *result = [HttpdnsResult new];
    result.host = ip;

    if (queryType & HttpdnsQueryIPTypeIpv4) {
        if ([HttpdnsUtil isIPv4Address:ip]) {
            result.ips = @[ip];
        }
    }

    if (queryType & HttpdnsQueryIPTypeIpv6) {
        if ([HttpdnsUtil isIPv6Address:ip]) {
            result.ipv6s = @[ip];
        }
    }

    return result;
}


- (NSString *)getIpByHostAsync:(NSString *)host {
    NSArray *ips = [self getIpsByHostAsync:host];
    if ([HttpdnsUtil isNotEmptyArray:ips]) {
        return ips[0];
    }
    return nil;
}

- (NSString *)getIPv4ForHostAsync:(NSString *)host {
    NSArray *ips = [self getIPv4ListForHostAsync:host];
    if ([HttpdnsUtil isNotEmptyArray:ips]) {
        return ips[0];
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

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4];
    [self attachAccountInfoToRequest:request];
    [request becomeNonBlockingRequest];
    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getV4Ips];
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

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4];
    [self attachAccountInfoToRequest:request];
    [request becomeNonBlockingRequest];
    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getV4Ips];
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
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4];
        [self attachAccountInfoToRequest:request];
        [request becomeNonBlockingRequest];
        HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
        if (hostObject) {
            NSArray * ipsObject = [hostObject getV4Ips];
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
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4];
        [self attachAccountInfoToRequest:request];
        [request becomeBlockingRequest];
        __block HttpdnsHostObject *hostObject = [self->_requestManager resolveHost:request];
        double end = [[NSDate date] timeIntervalSince1970] * 1000;
        HttpdnsLogDebug("###### getIPv4ListForHostSync result: %@, resolve time delta is %f ms", hostObject, (end - start));

        if (hostObject) {
            NSArray * ipsObject = [hostObject getV4Ips];
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
    if ([HttpdnsUtil isIPv6Address:IP]) {
        return [NSString stringWithFormat:@"[%@]", IP];
    }
    return IP;
}

- (NSString *)getIPv6ByHostAsync:(NSString *)host {
    NSArray *ips = [self getIPv6sByHostAsync:host];
    if ([HttpdnsUtil isNotEmptyArray:ips]) {
        return ips[0];
    }
    return nil;
}

- (NSString *)getIPv6ForHostAsync:(NSString *)host {
    NSArray *ips = [self getIPv6ListForHostAsync:host];
    if ([HttpdnsUtil isNotEmptyArray:ips]) {
        return ips[0];
    }
    return nil;
}

- (NSArray *)getIPv6sByHostAsync:(NSString *)host {
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

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv6];
    [self attachAccountInfoToRequest:request];
    [request becomeNonBlockingRequest];
    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (hostObject) {
        NSArray *ip6sObject = [hostObject getV6Ips];
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

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv6];
    [self attachAccountInfoToRequest:request];
    [request becomeNonBlockingRequest];
    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (hostObject) {
        NSArray *ip6sObject = [hostObject getV6Ips];
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
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv6];
        [self attachAccountInfoToRequest:request];
        [request becomeNonBlockingRequest];
        HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
        if (hostObject) {
            NSArray *ipv6List = [hostObject getV6Ips];
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
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv6];
        [self attachAccountInfoToRequest:request];
        [request becomeBlockingRequest];
        HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];

        if (hostObject) {
            NSArray * ipv6List = [hostObject getV6Ips];
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
    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        if ([HttpdnsUtil isIPv4Address:host]) {
            return @{ALICLOUDHDNS_IPV4: @[host?:@""]};
        } else if ([HttpdnsUtil isIPv6Address:host]) {
            return @{ALICLOUDHDNS_IPV6: @[host?:@""]};
        }
        return nil;
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6];
    [self attachAccountInfoToRequest:request];
    [request becomeNonBlockingRequest];
    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (hostObject) {
        NSArray *ip4s = [hostObject getV4IpStrings];
        NSArray *ip6s = [hostObject getV6IpStrings];
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
    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        if ([HttpdnsUtil isIPv4Address:host]) {
            return @{ALICLOUDHDNS_IPV4: @[host?:@""]};
        } else if ([HttpdnsUtil isIPv6Address:host]) {
            return @{ALICLOUDHDNS_IPV6: @[host?:@""]};
        }
        return nil;
    }

    if (![HttpdnsUtil isAHost:host]) {
        HttpdnsLogDebug("The host is illegal: %@", host);
        return nil;
    }

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6];
    [self attachAccountInfoToRequest:request];
    [request becomeNonBlockingRequest];
    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (hostObject) {
        NSArray *ip4s = [hostObject getV4IpStrings];
        NSArray *ip6s = [hostObject getV6IpStrings];
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
    if ([self _shouldDegradeHTTPDNS:host]) {
        return nil;
    }

    if (!host) {
        return nil;
    }

    if ([HttpdnsUtil isAnIP:host]) {
        HttpdnsLogDebug("The host is just an IP: %@", host);
        if ([HttpdnsUtil isIPv4Address:host]) {
            return @{ALICLOUDHDNS_IPV4: @[host?:@""]};
        } else if ([HttpdnsUtil isIPv6Address:host]) {
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
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6];
        [self attachAccountInfoToRequest:request];
        [request becomeNonBlockingRequest];
        HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
        if (hostObject) {
            NSArray *ip4s = [hostObject getV4IpStrings];
            NSArray *ip6s = [hostObject getV6IpStrings];
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
        HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6];
        [self attachAccountInfoToRequest:request];
        [request becomeBlockingRequest];
        HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
        if (hostObject) {
            NSArray *ip4s = [hostObject getV4IpStrings];
            NSArray *ip6s = [hostObject getV6IpStrings];
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
    HttpdnsIPStackType stackType = [[HttpdnsIpStackDetector sharedInstance] currentIpStack];
    NSMutableDictionary *ipv4_ipv6 = [NSMutableDictionary dictionary];
    if (stackType == kHttpdnsIpDual) {
        ipv4_ipv6 = [[self getIPv4_v6ByHostAsync:host] mutableCopy];
    } else if (stackType == kHttpdnsIpv4Only) {
        NSArray* ipv4Ips = [self getIpsByHostAsync:host];
        if (ipv4Ips != nil) {
            [ipv4_ipv6 setObject:ipv4Ips forKey:ALICLOUDHDNS_IPV4];
        }
    } else if (stackType == kHttpdnsIpv6Only) {
        NSArray* ipv6Ips = [self getIPv6sByHostAsync:host];
        if (ipv6Ips != nil) {
            [ipv4_ipv6 setObject:ipv6Ips forKey:ALICLOUDHDNS_IPV6];
        }
    }

    return ipv4_ipv6;
}

-(NSDictionary <NSString *, NSArray *>*)autoGetHttpDnsResultForHostAsync:(NSString *)host {
    HttpdnsIPStackType stackType = [[HttpdnsIpStackDetector sharedInstance] currentIpStack];
    NSMutableDictionary *httpdnsResult = [NSMutableDictionary dictionary];
    if (stackType == kHttpdnsIpDual) {
        httpdnsResult = [[self getHttpDnsResultHostAsync:host] mutableCopy];
    } else if (stackType == kHttpdnsIpv4Only) {
        NSArray* ipv4IpList = [self getIPv4ListForHostAsync:host];
        if (ipv4IpList) {
            [httpdnsResult setObject:ipv4IpList forKey:ALICLOUDHDNS_IPV4];
        }
    } else if (stackType == kHttpdnsIpv6Only) {
        NSArray* ipv6List = [self getIPv6ListForHostAsync:host];
        if (ipv6List) {
            [httpdnsResult setObject:ipv6List forKey:ALICLOUDHDNS_IPV6];
        }
    }

    return httpdnsResult;
}

- (NSDictionary <NSString *, NSArray *>*)autoGetHttpDnsResultForHostSync:(NSString *)host {
    HttpdnsIPStackType stackType = [[HttpdnsIpStackDetector sharedInstance] currentIpStack];
    NSMutableDictionary *httpdnsResult = [NSMutableDictionary dictionary];
    if (stackType == kHttpdnsIpv4Only) {
        NSArray* ipv4IpList = [self getIPv4ListForHostSync:host];
        if (ipv4IpList) {
            [httpdnsResult setObject:ipv4IpList forKey:ALICLOUDHDNS_IPV4];
        }
    } else if (stackType == kHttpdnsIpDual) {
        httpdnsResult = [[self getHttpDnsResultHostSync:host] mutableCopy];
    } else if (stackType == kHttpdnsIpv6Only) {
        NSArray* ipv6List = [self getIPv6ListForHostSync:host];
        if (ipv6List) {
            [httpdnsResult setObject:ipv6List forKey:ALICLOUDHDNS_IPV6];
        }
    }
    return httpdnsResult;
}

- (void)setLogHandler:(id<HttpdnsLoggerProtocol>)logHandler {
    if (logHandler != nil) {
        [HttpdnsLog setLogHandler:logHandler];
    } else {
        [HttpdnsLog unsetLogHandler];
    }
}

- (void)cleanHostCache:(NSArray<NSString *> *)hostArray {
    if ([HttpdnsUtil isEmptyArray:hostArray]) {
        [self cleanAllHostCache];
        return;
    }

    [_requestManager cleanMemoryAndPersistentCacheOfHostArray:hostArray];
}

- (void)cleanAllHostCache {
    [_requestManager cleanMemoryAndPersistentCacheOfAllHosts];
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
    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4 sdnsParams:params cacheKey:cacheKey];
    [self attachAccountInfoToRequest:request];
    [request becomeNonBlockingRequest];
    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getV4Ips];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        NSMutableDictionary * ipsDictionary = [[NSMutableDictionary alloc] init];
        [ipsDictionary setObject:host forKey:@"host"];
        if ([HttpdnsUtil isNotEmptyString:hostObject.extra]) {
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

- (BOOL)_shouldDegradeHTTPDNS:(NSString *)host {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (self.delegate && [self.delegate respondsToSelector:@selector(shouldDegradeHTTPDNS:)]) {
        return [self.delegate shouldDegradeHTTPDNS:host];
    }
#pragma clang diagnostic pop
    return NO;
}

#pragma mark -
#pragma mark -------------- HttpdnsRequestScheduler_Internal

- (NSTimeInterval)authTimeOffset {
    return _authTimeOffset;
}

- (NSString *)getIpByHost:(NSString *)host {
    NSArray *ips = [self getIpsByHost:host];
    if ([HttpdnsUtil isNotEmptyArray:ips]) {
        return ips[0];
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

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:host queryIpType:HttpdnsQueryIPTypeIpv4];
    [self attachAccountInfoToRequest:request];
    [request becomeBlockingRequest];
    HttpdnsHostObject *hostObject = [_requestManager resolveHost:request];
    if (hostObject) {
        NSArray * ipsObject = [hostObject getV4Ips];
        NSMutableArray *ipsArray = [[NSMutableArray alloc] init];
        if ([HttpdnsUtil isNotEmptyArray:ipsObject]) {
            for (HttpdnsIpObject *ipObject in ipsObject) {
                [ipsArray addObject:[ipObject getIpString]];
            }
            return ipsArray;
        }
    }
    return nil;
}

- (NSString *)getIpByHostInURLFormat:(NSString *)host {
    NSString *IP = [self getIpByHost:host];
    if ([HttpdnsUtil isIPv6Address:IP]) {
        return [NSString stringWithFormat:@"[%@]", IP];
    }
    return IP;
}

@end
