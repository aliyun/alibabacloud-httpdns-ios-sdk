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

#import "HttpdnsScheduleCenter.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsLog.h"
#import "HttpdnsConstants.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsScheduleCenterRequest.h"
#import "HttpdnsRequest.h"
#import "HttpdnsScheduleCenter_Internal.h"

NSInteger ALICLOUD_HTTPDNS_RESET_IP_LIST_TIME_DAY = 1;

static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_RESULT_CACHE_FILE_NAME = @"schedule_center_result";

static NSString *const ALICLOUD_HTTPDNS_NEED_FETCH_FROM_SCHEDULE_CENTER_STATUS_CACHE_FILE_NAME = @"need_fetch_from_schedule_center_status";
static NSString *const ALICLOUD_HTTPDNS_NEED_FETCH_FROM_SCHEDULE_CENTER_STATUS_CACHE_KEY = @"need_fetch_from_schedule_center_status_key";
NSArray *ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST = nil;

@interface HttpdnsScheduleCenter ()

@property (nonatomic, copy) NSDictionary *scheduleCenterResult;

@property (nonatomic, assign, getter=isStopService) BOOL stopService;

@property (nonatomic, assign, getter=doHaveNewIPList) BOOL haveNewIPList;

@property (nonatomic, strong) dispatch_queue_t scheduleCenterResultQueue;
@property (nonatomic, strong) dispatch_queue_t connectToScheduleCenterQueue;
@property (nonatomic, strong) dispatch_queue_t needToFetchFromScheduleCenterQueue;
@property (nonatomic, strong) dispatch_queue_t cacheActivatedServerIPStatusQueue;

@property (nonatomic, copy) NSString *activatedIPIndexPath;

@property (nonatomic, strong) NSDate *lastScheduleCenterConnectDate;

@property (nonatomic, copy) NSString *needFetchFromScheduleCenterStatusPath;

@end

@implementation HttpdnsScheduleCenter
@synthesize scheduleCenterResult = _scheduleCenterResult;
@synthesize activatedServerIPIndex = _activatedServerIPIndex;

/**
 * create a singleton instance of HttpdnsScheduleCenter
 */
+ (instancetype)sharedInstance {
    static HttpdnsScheduleCenter *_sharedHttpdnsScheduleCenter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedHttpdnsScheduleCenter = [[super allocWithZone:NULL] init];
    });
    return _sharedHttpdnsScheduleCenter;
}

+ (id)allocWithZone:(NSZone *)zone {
    return [self sharedInstance];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

/**
 *  lazy load lastScheduleCenterConnectDate
 *
 *  @return NSDate
 */
- (NSDate *)lastScheduleCenterConnectDate {
    __block NSDate *lastScheduleCenterConnectDate = nil;
    dispatch_sync(self.connectToScheduleCenterQueue, ^{
        lastScheduleCenterConnectDate = _lastScheduleCenterConnectDate;
    });
    return lastScheduleCenterConnectDate;
}

/**
 * able to connect to schedule center
 * 可以请求SC，也即：每次请求必须有一定时间的间隔。
 */
- (BOOL)isAbleToConnectToScheduleCenter {
    //需要考虑首次启动，值为nil
    if (!self.lastScheduleCenterConnectDate) {
        return YES;
    }
    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:self.lastScheduleCenterConnectDate];
    BOOL isAbleToConnectToScheduleCenter = (timeInterval > ALICLOUD_HTTPDNS_ABLE_TO_CONNECT_SCHEDULE_CENTER_INTERVAL);
    return isAbleToConnectToScheduleCenter;
}

+ (void)initialize {
    [self configurescheduleCenterResultCacheTimeoutInterval];
}

- (instancetype)init {
    if (self = [super init]) {
        _scheduleCenterResultQueue = dispatch_queue_create("com.scheduleCenterResultQueue.httpdns", DISPATCH_QUEUE_SERIAL);
        _connectToScheduleCenterQueue = dispatch_queue_create("com.connectToScheduleCenterQueue.httpdns", DISPATCH_QUEUE_SERIAL);
        _needToFetchFromScheduleCenterQueue = dispatch_queue_create("com.needToFetchFromScheduleCenterQueue.httpdns", DISPATCH_QUEUE_SERIAL);
        _activatedServerIPIndex = 0;
        [self initActivatedServerIPIndex];
        [self initScheduleCenterResultFromCache];
        [self upateIPListIfNeededAsync];
        _scheduleCenterTestHelper = [[HttpdnsScheduleCenterTestHelper alloc] init];
    }
    return self;
}

- (void)upateIPListIfNeededAsync {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        if (![self needToFetchFromScheduleCenter]) {
            return;
        }
        [self forceUpdateIpListAsync];
    });
    
}

- (void)forceUpdateIpListAsync {
    [self forceUpdateIpListAsyncWithCallback:nil];
}

- (void)forceUpdateIpListAsyncWithCallback:(HttpDnsIdCallback)callback {
    if (!self.isAbleToConnectToScheduleCenter) {
        !callback ?: callback(nil);
        return;
    }
    HttpdnsLogDebug("begin fetch ip list status");
    [self updateIpListAsyncWithCallback:^(NSDictionary *result) {
        if (result) {
            //隔一段时间请求一次，仅仅从请求成功后开始计时，防止弱网情况下，频频超时但无法访问SC。
            [self setNeedToFetchFromScheduleCenter:NO];
            [self setScheduleCenterResult:result];
            HttpdnsLogDebug("fetch ip list status succeed");
            //从服务端获取到新的IP列表后，取消disable状态，置为
            HttpDnsService *serviceProvider = [HttpDnsService sharedInstance];
            HttpdnsRequestScheduler *requestScheduler = serviceProvider.requestScheduler;
            [requestScheduler setServerDisable:NO host:nil];
            [self setActivatedServerIPIndex:0];
            !callback ?: callback(result);
            return;
        }
        !callback ?: callback(nil);
    }];
}


- (void)updateIpListAsyncWithCallback:(HttpDnsIdCallback)callback {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        self.connectingWithScheduleCenter = YES;
        dispatch_async(self.connectToScheduleCenterQueue, ^(void) {
            _lastScheduleCenterConnectDate = [NSDate date];
        });
        
        HttpdnsScheduleCenterRequest *scheduleCenterRequest = [HttpdnsScheduleCenterRequest new];
        NSDictionary *queryScheduleCenterRecord = [scheduleCenterRequest queryScheduleCenterRecordFromServerSync];
//        dispatch_async(dispatch_get_main_queue(),^{
            !callback ?: callback(queryScheduleCenterRecord);
            self.connectingWithScheduleCenter = NO;
//        });
    });
}

- (BOOL)needToFetchFromScheduleCenter {
    __block BOOL needToFetchFromScheduleCenter = YES;
    dispatch_sync(self.needToFetchFromScheduleCenterQueue,^{
        BOOL value;
        id json = [HttpdnsPersistenceUtils getJSONFromDirectory:[HttpdnsPersistenceUtils needFetchFromScheduleCenterStatusPatch]
                                                       fileName:ALICLOUD_HTTPDNS_NEED_FETCH_FROM_SCHEDULE_CENTER_STATUS_CACHE_FILE_NAME
                                                        timeout:ALICLOUD_HTTPDNS_NEED_FETCH_IP_LIST_STATUS_CACHE_TIMEOUT_INTERVAL];
        if (!json) {
            HttpdnsLogDebug("need fetch ip list status");
            return;
        }
        
        @try {
            value = [json[ALICLOUD_HTTPDNS_NEED_FETCH_FROM_SCHEDULE_CENTER_STATUS_CACHE_KEY] boolValue];
        } @catch (NSException *exception) {}
        
        if (value) {
            HttpdnsLogDebug("need fetch ip list status");
        }
        needToFetchFromScheduleCenter = value;
    });
    return needToFetchFromScheduleCenter;
}

- (void)setNeedToFetchFromScheduleCenter:(BOOL)needToFetchFromScheduleCenter {
    dispatch_async(self.needToFetchFromScheduleCenterQueue, ^{
        NSString *fileName = [self needFetchFromScheduleCenterStatusPath];
        if (needToFetchFromScheduleCenter) {
            HttpdnsLogDebug("Must fetch ip list status next time");
            [HttpdnsPersistenceUtils removeFile:fileName];
            return;
        }
        NSDictionary *dictionary = @{
                                     ALICLOUD_HTTPDNS_NEED_FETCH_FROM_SCHEDULE_CENTER_STATUS_CACHE_KEY : @(needToFetchFromScheduleCenter)
                                     };
        [HttpdnsPersistenceUtils saveJSON:dictionary toPath:fileName];
        HttpdnsLogDebug("There is no need to fetch ip list status next time");
    });
}

- (NSString *)scheduleCenterResultPath {
    if (_scheduleCenterResultPath) {
        return _scheduleCenterResultPath;
    }
    NSString *fullPath = [[self class] scheduleCenterResultPath];
    _scheduleCenterResultPath = fullPath;
    return _scheduleCenterResultPath;
}

+ (NSString *)scheduleCenterResultPath {
    NSString *fileName = ALICLOUD_HTTPDNS_SCHEDULE_CENTER_RESULT_CACHE_FILE_NAME;
    NSString *fullPath = [[HttpdnsPersistenceUtils scheduleCenterResultPath] stringByAppendingPathComponent:fileName];
    return fullPath;
}

- (NSString *)needFetchFromScheduleCenterStatusPath {
    if (_needFetchFromScheduleCenterStatusPath) {
        return _needFetchFromScheduleCenterStatusPath;
    }
    NSString *fileName = ALICLOUD_HTTPDNS_NEED_FETCH_FROM_SCHEDULE_CENTER_STATUS_CACHE_FILE_NAME;
    NSString *fullPath = [[HttpdnsPersistenceUtils needFetchFromScheduleCenterStatusPatch] stringByAppendingPathComponent:fileName];
    _needFetchFromScheduleCenterStatusPath = fullPath;
    return _needFetchFromScheduleCenterStatusPath;
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

+ (void)configurescheduleCenterResultCacheTimeoutInterval {
    ALICLOUD_HTTPDNS_NEED_FETCH_IP_LIST_STATUS_CACHE_TIMEOUT_INTERVAL = 24 * 60 * 60; /**< 一天 */
    ALICLOUD_HTTPDNS_ABLE_TO_CONNECT_SCHEDULE_CENTER_INTERVAL = 5 * 60; /**< 五分钟 */
    ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST = @[
                                                   ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP,
                                                   ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP_2,
                                                   ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST
                                                   ];

}

- (void)initActivatedServerIPIndex {
    dispatch_async(self.cacheActivatedServerIPStatusQueue, ^{
        NSInteger oldServerIPIndex = _activatedServerIPIndex;
        NSDictionary *json = [HttpdnsPersistenceUtils getJSONFromDirectory:[HttpdnsPersistenceUtils activatedIPIndexPath]
                                                                  fileName:ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_CACHE_FILE_NAME];
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

- (void)initScheduleCenterResultFromCache {
    dispatch_async(self.scheduleCenterResultQueue, ^{
        //IP List 没有过期时间，仅仅在 fetch SC 后更新。
        NSDictionary *scheduleCenterResult = [HttpdnsPersistenceUtils getJSONFromDirectory:[HttpdnsPersistenceUtils scheduleCenterResultPath]
                                                                                  fileName:ALICLOUD_HTTPDNS_SCHEDULE_CENTER_RESULT_CACHE_FILE_NAME];
        if (!scheduleCenterResult) {
            return;
        }
        
        if ([scheduleCenterResult isKindOfClass:[NSDictionary class]]) {
            [self setScheduleCenterResultAndOtherStatus:scheduleCenterResult];
        }
    });
}

- (void)setScheduleCenterResult:(NSDictionary *)scheduleCenterResult {
    dispatch_async(self.scheduleCenterResultQueue, ^{
        if (_scheduleCenterResult == scheduleCenterResult) {
            return;
        }
        [self setScheduleCenterResultAndOtherStatus:scheduleCenterResult];
        
        if (!scheduleCenterResult) {
            [HttpdnsPersistenceUtils removeFile:self.scheduleCenterResultPath];
            return;
        }
        BOOL saveSucceed = [HttpdnsPersistenceUtils saveJSON:scheduleCenterResult toPath:self.scheduleCenterResultPath];
        HttpdnsLogDebug("ip list %@", saveSucceed ? @"save succeed" : @"save fail");
    });
}

- (void)setScheduleCenterResultAndOtherStatus:(NSDictionary *)scheduleCenterResult {
    dispatch_async(self.scheduleCenterResultQueue, ^{
        _scheduleCenterResult = scheduleCenterResult;
        @try {
            NSString *stopServiceValue = _scheduleCenterResult[ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_KEY];
            _stopService = ([stopServiceValue isEqualToString:ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_DISABLE_VALUE]);
        } @catch (NSException *exception) {}
        @try {
            _IPList = _scheduleCenterResult[ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_IP_KEY];
        } @catch (NSException *exception) {}
    });
}

- (NSDictionary *)scheduleCenterResult {
    __block NSDictionary *scheduleCenterResult = nil;
    dispatch_sync(self.scheduleCenterResultQueue, ^{
        scheduleCenterResult = _scheduleCenterResult;
    });
    return scheduleCenterResult;
}

- (BOOL)isStopService {
    __block BOOL isStopService = NO;
    dispatch_sync(self.scheduleCenterResultQueue, ^{
        isStopService = _stopService;
    });
    return isStopService;
}

- (NSArray *)IPList {
    __block NSArray *IPList = nil;
    dispatch_sync(self.scheduleCenterResultQueue, ^{
        IPList = _IPList;
    });
    return IPList ?: ALICLOUD_HTTPDNS_SERVER_IP_LIST;
}

- (NSString *)getActivatedServerIPWithIndex:(NSInteger)index {
    NSString *serverIP = nil;
    @try {
        serverIP = self.IPList[index];
    } @catch (NSException *exception) {
        serverIP = self.IPList[0];
    }
    return serverIP;
}

- (void)changeToNextServerIPIndexFromIPIndex:(NSInteger)IPIndex {
    NSInteger nextServerIPIndex = [self nextServerIPIndexFromIPIndex:IPIndex increase:1];
    self.activatedServerIPIndex = nextServerIPIndex;
    if (nextServerIPIndex == 0) {
        [self forceUpdateIpListAsync];
    }
}

- (NSInteger)nextServerIPIndexFromIPIndex:(NSInteger)IPIndex increase:(NSInteger)increase {
    NSInteger nextServerIPIndex = ((IPIndex + increase) % self.IPList.count);
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

@end

@implementation HttpdnsScheduleCenterTestHelper

+ (void)shortAutoConnectToScheduleCenterInterval {
    ALICLOUD_HTTPDNS_NEED_FETCH_IP_LIST_STATUS_CACHE_TIMEOUT_INTERVAL = 10;  /**< 由24小时改为10S */
}

+ (void)shortMixConnectToScheduleCenterInterval {
    ALICLOUD_HTTPDNS_ABLE_TO_CONNECT_SCHEDULE_CENTER_INTERVAL = 5;/**< 由5MIN改为5S */
}

+ (void)zeroAutoConnectToScheduleCenterInterval {
    ALICLOUD_HTTPDNS_NEED_FETCH_IP_LIST_STATUS_CACHE_TIMEOUT_INTERVAL = 0;  /**< 由24小时改为0S */
}

+ (void)zeroMixConnectToScheduleCenterInterval {
    ALICLOUD_HTTPDNS_ABLE_TO_CONNECT_SCHEDULE_CENTER_INTERVAL = 0;/**< 由5MIN改为0S */
}

+ (void)setFirstTwoWrongForScheduleCenterIPs {
    ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST = @[
                                                   @"100.100.100.100",
                                                   @"101.101.101.101",
                                                   ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST
                                                   ];
}

+ (void)setAllWrongForScheduleCenterIPs {
    ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST = @[
                                                   @"100.100.100.100",
                                                   @"101.101.101.101",
                                                   @"102.102.102.102"
                                                   ];
}

//ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST = @[
//                                               ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP,
//                                               ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP_2,
//                                               ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST
//                                               ];
@end
