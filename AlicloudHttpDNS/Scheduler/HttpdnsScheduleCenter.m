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
#import "HttpdnsLog_Internal.h"
#import "HttpdnsInternalConstant.h"
#import "HttpdnsRequestManager.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsScheduleExecutor.h"
#import "HttpdnsRemoteResolver.h"
#import "HttpdnsUtil.h"
#import "HttpdnsPublicConstant.h"
#import "HttpdnsRegionConfigLoader.h"
#import "HttpdnsIpStackDetector.h"

static NSString *const kLastUpdateUnixTimestampKey = @"last_update_unix_timestamp";
static NSString *const kScheduleRegionConfigLocalCacheFileName = @"schedule_center_result";

static int const MAX_UPDATE_RETRY_COUNT = 2;

@interface HttpdnsScheduleCenter ()

// 为了简单，无论v4还是v6，都只共同维护1个下标
// 一般而言，下标当前在哪里并不是那么重要，重要的是轮询的能力
@property (nonatomic, assign) int currentActiveServiceHostIndex;
@property (nonatomic, assign) int currentActiveUpdateHostIndex;

@property (nonatomic, copy) NSArray<NSString *> *ipv4ServiceServerHostList;
@property (nonatomic, copy) NSArray<NSString *> *ipv6ServiceServerHostList;

@property (nonatomic, copy) NSArray<NSString *> *ipv4UpdateServerHostList;
@property (nonatomic, copy) NSArray<NSString *> *ipv6UpdateServerHostList;

@property (nonatomic, strong) dispatch_queue_t scheduleFetchConfigAsyncQueue;
@property (nonatomic, strong) dispatch_queue_t scheduleConfigLocalOperationQueue;

@property (nonatomic, copy) NSString *scheduleCenterResultPath;
@property (nonatomic, copy) NSDate *lastScheduleCenterConnectDate;

@property (nonatomic, copy) NSString *currentRegion;

@end

@implementation HttpdnsScheduleCenter

+ (instancetype)sharedInstance {
    static HttpdnsScheduleCenter *sharedHttpdnsScheduleCenter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedHttpdnsScheduleCenter = [[HttpdnsScheduleCenter alloc] init];
    });
    return sharedHttpdnsScheduleCenter;
}

- (instancetype)init {
    if (self = [super init]) {
        _scheduleFetchConfigAsyncQueue = dispatch_queue_create("com.aliyun.httpdns.scheduleFetchConfigAsyncQueue", DISPATCH_QUEUE_CONCURRENT);
        _scheduleConfigLocalOperationQueue = dispatch_queue_create("com.aliyun.httpdns.scheduleConfigLocalOperationQueue", DISPATCH_QUEUE_SERIAL);

        _currentActiveUpdateHostIndex = 0;
        _currentActiveServiceHostIndex = 0;

        _scheduleCenterResultPath = [[HttpdnsPersistenceUtils scheduleCenterResultDirectory]
                                     stringByAppendingPathComponent:kScheduleRegionConfigLocalCacheFileName];

        // 上次更新日期默认设置为1天前，这样如果缓存没有记录，就会立即更新
        _lastScheduleCenterConnectDate = [NSDate dateWithTimeIntervalSinceNow:(- 24 * 60 * 60)];
    }
    return self;
}

- (void)initRegion:(NSString *)region {
    if (![[HttpdnsRegionConfigLoader getAvailableRegionList] containsObject:region]) {
        region = ALICLOUD_HTTPDNS_DEFAULT_REGION_KEY;
    }

    // 先用默认region初始化
    // 如果用户主动调用了设置region接口，会按照用户设置的再来一次
    [self initServerListByRegion:region];

    // 再从本地缓存读取之前缓存过的配置
    [self loadRegionConfigFromLocalCache];
}

- (void)resetRegion:(NSString *)region {
    [self initServerListByRegion:region];

    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        self.currentActiveServiceHostIndex = 0;
        self.currentActiveUpdateHostIndex = 0;
    });

    // 重置region之后马上发起一次更新
    [self asyncUpdateRegionScheduleConfig];
}

- (void)loadRegionConfigFromLocalCache {
    dispatch_async(self.scheduleFetchConfigAsyncQueue, ^{
        NSDictionary *scheduleCenterResult = [HttpdnsPersistenceUtils getJSONFromPath:self.scheduleCenterResultPath];

        if (!scheduleCenterResult) {
            return;
        }

        NSNumber *lastUpdateUnixTimestamp = [scheduleCenterResult objectForKey:kLastUpdateUnixTimestampKey];
        if (lastUpdateUnixTimestamp) {
            NSDate *lastUpdateDate = [NSDate dateWithTimeIntervalSince1970:lastUpdateUnixTimestamp.doubleValue];
            self->_lastScheduleCenterConnectDate = lastUpdateDate;
        }
        [self updateRegionConfig:scheduleCenterResult];
    });
}

// 根据指定的时间间隔检查是否需要更新
- (void)asyncUpdateRegionConfigAfterAtLeast:(NSTimeInterval)interval {
    __block BOOL shouldUpdate = NO;
    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        NSDate *now = [NSDate date];
        if ([now timeIntervalSinceDate:self->_lastScheduleCenterConnectDate] > interval) {
            self->_lastScheduleCenterConnectDate = now;
            shouldUpdate = YES;
        }
    });

    if (shouldUpdate) {
        [self asyncUpdateRegionScheduleConfig];
    }
}

- (void)asyncUpdateRegionScheduleConfig {
    [self asyncUpdateRegionScheduleConfigAtRetry:0];
}

- (void)asyncUpdateRegionScheduleConfigAtRetry:(int)retryCount {
    if (retryCount > MAX_UPDATE_RETRY_COUNT) {
        return;
    }

    dispatch_async(_scheduleFetchConfigAsyncQueue, ^(void) {
        HttpdnsScheduleExecutor *scheduleCenterExecutor = [HttpdnsScheduleExecutor new];

        NSError *error = nil;
        NSString *updateHost = [self getActiveUpdateServerHost];
        NSDictionary *scheduleCenterResult = [scheduleCenterExecutor fetchRegionConfigFromServer:updateHost error:&error];
        if (error || !scheduleCenterResult) {
            HttpdnsLogDebug("Update region config failed, error: %@", error);

            // 只有报错了就尝试选择新的调度服务器
            [self moveToNextUpdateServerHost];

            // 3秒之后重试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((retryCount + 1) * NSEC_PER_SEC)), self->_scheduleFetchConfigAsyncQueue, ^{
                [self asyncUpdateRegionScheduleConfigAtRetry:retryCount + 1];
            });

            return;
        }

        NSMutableDictionary *toSave = [scheduleCenterResult mutableCopy];
        toSave[kLastUpdateUnixTimestampKey] = @([[NSDate date] timeIntervalSince1970]);

        BOOL saveSuccess = [HttpdnsPersistenceUtils saveJSON:toSave toPath:self.scheduleCenterResultPath];
        HttpdnsLogDebug("Save region config to local cache %@", saveSuccess ? @"successfully" : @"failed");

        [self updateRegionConfig:scheduleCenterResult];
    });
}

- (void)updateRegionConfig:(NSDictionary *)scheduleCenterResult {
    NSArray *v4Result = [scheduleCenterResult objectForKey:kAlicloudHttpdnsRegionConfigV4HostKey];
    NSArray *v6Result = [scheduleCenterResult objectForKey:kAlicloudHttpdnsRegionConfigV6HostKey];

    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        HttpdnsRegionConfigLoader *regionConfigLoader = [HttpdnsRegionConfigLoader sharedInstance];

        if ([HttpdnsUtil isNotEmptyArray:v4Result]) {
            self->_ipv4ServiceServerHostList = [v4Result copy];

            // 调度server列表总是服务server列表加上兜底域名
            self->_ipv4UpdateServerHostList = [HttpdnsUtil joinArrays:v4Result
                                                            withArray:[regionConfigLoader getUpdateV4FallbackHostList:self->_currentRegion]];
        }

        if ([HttpdnsUtil isNotEmptyArray:v6Result]) {
            self->_ipv6ServiceServerHostList = [v6Result copy];

            // 调度server列表总是服务server列表加上兜底域名
            self->_ipv6UpdateServerHostList = [HttpdnsUtil joinArrays:v6Result
                                                            withArray:[regionConfigLoader getUpdateV6FallbackHostList:self->_currentRegion]];
        }

        self->_currentActiveUpdateHostIndex = 0;
        self->_currentActiveServiceHostIndex = 0;
    });
}

- (NSString *)getActiveUpdateServerHost {
    HttpdnsIPStackType currentStack = [[HttpdnsIpStackDetector sharedInstance] currentIpStack];
    if (currentStack == kHttpdnsIpv6Only) {
        NSString *v6Host = [self currentActiveUpdateServerV6Host];
        if ([HttpdnsUtil isIPv6Address:v6Host]) {
            return [NSString stringWithFormat:@"[%@]", v6Host];
        }
        return v6Host;
    }

    return [self currentActiveUpdateServerV4Host];
}

- (void)initServerListByRegion:(NSString *)region {
    self->_currentRegion = region;

    HttpdnsRegionConfigLoader *regionConfigLoader = [HttpdnsRegionConfigLoader sharedInstance];

    self.ipv4ServiceServerHostList = [regionConfigLoader getSeriveV4HostList:region];
    self.ipv4UpdateServerHostList = [HttpdnsUtil joinArrays:[regionConfigLoader getSeriveV4HostList:region]
                                                  withArray:[regionConfigLoader getUpdateV4FallbackHostList:region]];

    self.ipv6ServiceServerHostList = [regionConfigLoader getSeriveV6HostList:region];
    self.ipv6UpdateServerHostList = [HttpdnsUtil joinArrays:[regionConfigLoader getSeriveV6HostList:region]
                                                  withArray:[regionConfigLoader getUpdateV6FallbackHostList:region]];
}

- (void)moveToNextServiceServerHost {
    __block int timeToUpdate = NO;
    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        self.currentActiveServiceHostIndex++;

        int total = (int)self.ipv4ServiceServerHostList.count + (int)self.ipv6ServiceServerHostList.count;
        if (self.currentActiveServiceHostIndex % total == 0) {
            timeToUpdate = YES;
        }
    });

    if (timeToUpdate) {
        // 每次服务server列表轮转之后，尝试1个至少间隔30秒的更新
        [self asyncUpdateRegionConfigAfterAtLeast:30];
    }
}

- (void)moveToNextUpdateServerHost {
    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        self.currentActiveUpdateHostIndex++;
    });
}

- (NSString *)currentActiveUpdateServerV4Host {
    __block NSString *host = nil;
    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        int count = (int)self.ipv4UpdateServerHostList.count;
        if (count == 0) {
            HttpdnsLogDebug("Severe error: update v4 ip list is empty, it should never happen");
            return;
        }
        int index = self.currentActiveUpdateHostIndex % count;
        host = self.ipv4UpdateServerHostList[index];
    });
    return host;
}

- (NSString *)currentActiveServiceServerV4Host {
    // 每次读取时都检查是否需要更新，相当于实现一个懒加载的机制
    // 因为当前httpdns的初始化方式，没有一个统一的初始化入口，所以需要这样处理
    [self asyncUpdateRegionConfigAfterAtLeast:(24 * 60 * 60)];

    __block NSString *host = nil;
    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        int count = (int)self.ipv4ServiceServerHostList.count;
        if (count == 0) {
            HttpdnsLogDebug("Severe error: service v4 ip list is empty, it should never happen");
            return;
        }
        int index = self.currentActiveServiceHostIndex % count;
        host = self.ipv4ServiceServerHostList[index];
    });
    return host;
}

- (NSString *)currentActiveUpdateServerV6Host {
    __block NSString *host = nil;
    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        int count = (int)self.ipv6UpdateServerHostList.count;
        if (count == 0) {
            HttpdnsLogDebug("Severe error: update v6 ip list is empty, it should never happen");
            return;
        }
        int index = self.currentActiveUpdateHostIndex % count;
        host = self.ipv6UpdateServerHostList[index];
    });
    return host;
}

- (NSString *)currentActiveServiceServerV6Host {
    // 同上
    [self asyncUpdateRegionConfigAfterAtLeast:(24 * 60 * 60)];

    __block NSString *host = nil;
    dispatch_sync(_scheduleConfigLocalOperationQueue, ^{
        int count = (int)self.ipv6ServiceServerHostList.count;
        if (count == 0) {
            HttpdnsLogDebug("Severe error: service v6 ip list is empty, it should never happen");
            return;
        }
        int index = self.currentActiveServiceHostIndex % count;
        host = self.ipv6ServiceServerHostList[index];
    });

    if ([HttpdnsUtil isIPv6Address:host]) {
        host = [NSString stringWithFormat:@"[%@]", host];
    }
    return host;
}

#pragma mark - For Test Only

- (NSArray<NSString *> *)currentUpdateServerV4HostList {
    return self.ipv4UpdateServerHostList;
}

- (NSArray<NSString *> *)currentServiceServerV4HostList {
    return self.ipv4ServiceServerHostList;
}

- (NSArray<NSString *> *)currentUpdateServerV6HostList {
    return self.ipv6UpdateServerHostList;
}

- (NSArray<NSString *> *)currentServiceServerV6HostList {
    return self.ipv6ServiceServerHostList;
}

- (int)currentActiveUpdateServerHostIndex {
    return self.currentActiveUpdateHostIndex;
}

- (int)currentActiveServiceServerHostIndex {
    return self.currentActiveServiceHostIndex;
}

@end
