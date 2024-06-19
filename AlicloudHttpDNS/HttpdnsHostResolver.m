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

#import "HttpdnsService.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsHostResolver.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsConfig.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsConstants.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsgetNetworkInfoHelper.h"
#import "HttpdnsIPv6Manager.h"
#import "HttpdnsConfig.h"
#import "HttpdnsRequestScheduler.h"


NSInteger const ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE = 10003;
NSInteger const ALICLOUD_HTTPDNS_HTTP_COMMON_ERROR_CODE = 10004;
NSInteger const ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE = 10005;
NSInteger const ALICLOUD_HTTPDNS_HTTP_STREAM_READ_ERROR_CODE = 10006;
NSInteger const ALICLOUD_HTTPDNS_HTTPS_TIMEOUT_ERROR_CODE = -1001;
NSInteger const ALICLOUD_HTTPDNS_HTTP_CANNOT_CONNECT_SERVER_ERROR_CODE = -1004;
NSInteger const ALICLOUD_HTTPDNS_HTTP_USER_LEVEL_CHANGED_ERROR_CODE = 403;

NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_KEY = @"activated_IP_index_key";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_CACHE_FILE_NAME = @"activated_IP_index";

static dispatch_queue_t _runloopOperateQueue = 0;
static dispatch_queue_t _errorOperateQueue = 0;

static NSURLSession *_resolveHOSTSession = nil;

@interface HttpdnsHostResolver () <NSStreamDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) NSRunLoop *runloop;
@property (nonatomic, strong) NSError *networkError;

@end


@implementation HttpdnsHostResolver {
    NSMutableData *_resultData;
    dispatch_semaphore_t _sem;
    NSInputStream *_inputStream;
    BOOL _responseResolved;
    BOOL _compeleted;
    NSTimer *_timeoutTimer;
    NSDictionary *_httpJSONDict;
}
@synthesize runloop = _runloop;
@synthesize networkError = _networkError;

#pragma mark init

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _runloopOperateQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.runloopOperateQueue.HttpdnsRequest", DISPATCH_QUEUE_SERIAL);
        _errorOperateQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.errorOperateQueue.HttpdnsRequest", DISPATCH_QUEUE_SERIAL);
    });
}

- (NSRunLoop *)runloop {
    __block NSRunLoop *runloop = nil;
    dispatch_sync(_runloopOperateQueue, ^{
        runloop = _runloop;
    });
    return runloop;
}

- (void)setRunloop:(NSRunLoop *)runloop {
    dispatch_sync(_runloopOperateQueue, ^{
        _runloop = runloop;
    });
};

- (NSError *)networkError {
    __block NSError *networkError = nil;
    dispatch_sync(_errorOperateQueue, ^{
        networkError = _networkError;
    });
    return networkError;
}

- (void)setNetworkError:(NSError *)networkError {
    dispatch_sync(_errorOperateQueue, ^{
        _networkError = networkError;
    });
}

- (instancetype)init {
    if (self = [super init]) {
        [self resetRequestConfigure];
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
            _resolveHOSTSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        });
    }
    return self;
}

- (void)resetRequestConfigure {
    _sem = dispatch_semaphore_create(0);
    _resultData = [NSMutableData data];
    _httpJSONDict = nil;
    self.networkError = nil;
    _responseResolved = NO;
    _compeleted = NO;
}

#pragma mark LookupIpAction

- (HttpdnsHostObject *)parseHostInfoFromHttpResponse:(NSDictionary *)json withHostStr:(NSString *)host withQueryIpType:(HttpdnsQueryIPType)queryIpType {
    if (!json) {
        return nil;
    }

    NSDictionary *extra;
    if ([[json allKeys] containsObject:@"extra"]) {
        extra = [self htmlEntityDecode:[HttpdnsUtil safeObjectForKey:@"extra" dict:json]];
    }

    NSArray *ip4s = [HttpdnsUtil safeObjectForKey:@"ips" dict:json];
    if (!ip4s) {
        ip4s = @[];
    }

    NSArray *ip6s = [HttpdnsUtil safeObjectForKey:@"ipsv6" dict:json];
    if (!ip6s) {
        ip6s = @[];
    }

    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];

    // 处理ipv4
    NSMutableArray *ipArray = [NSMutableArray array];
    for (NSString *ip in ip4s) {
        if ([HttpdnsUtil isEmptyString:ip]) {
            continue;
        }
        HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
        [ipObject setIp:ip];
        [ipArray addObject:ipObject];
    }

    // 处理IPv6
    NSMutableArray *ip6Array = [NSMutableArray array];
    if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        for (NSString *ipv6 in ip6s) {
            if ([HttpdnsUtil isEmptyString:ipv6]) {
                continue;
            }
            HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
            [ipObject setIp:ipv6];
            [ip6Array addObject:ipObject];
        }
    }

    // 返回 额外返回一个extra字段
    if ([[json allKeys] containsObject:@"extra"]) {
        [hostObject setExtra:extra];
    }
    [hostObject setHostName:host];
    [hostObject setIps:ipArray];
    [hostObject setIp6s:ip6Array];

    int64_t ttlInSecond = [[json objectForKey:@"ttl"] longLongValue];

    // 自定义ttl
    HttpDnsService *dnsService = [HttpDnsService sharedInstance];
    if (dnsService.ttlDelegate && [dnsService.ttlDelegate respondsToSelector:@selector(httpdnsHost:ipType:ttl:)]) {
        AlicloudHttpDNS_IPType ipType;
        if (queryIpType & HttpdnsQueryIPTypeIpv4 && queryIpType & HttpdnsQueryIPTypeIpv6) {
            ipType = AlicloudHttpDNS_IPTypeV64;
        } else if (queryIpType & HttpdnsQueryIPTypeIpv6) {
            ipType = AlicloudHttpDNS_IPTypeV6;
        } else {
            ipType = AlicloudHttpDNS_IPTypeV4;
        }

        ttlInSecond = [dnsService.ttlDelegate httpdnsHost:host ipType:ipType ttl:ttlInSecond];
    }

    // 原ttl字段，实际会从外部接口返回的，只有下面的v4ttl和v6ttl
    [hostObject setTTL:ttlInSecond];

    // 分别设置 v4ttl v6ttl
    if ([HttpdnsUtil isNotEmptyArray:ipArray]) {
        [hostObject setV4TTL:ttlInSecond];
        hostObject.lastIPv4LookupTime = [HttpdnsUtil currentEpochTimeInSecond];
    }
    if ([HttpdnsUtil isNotEmptyArray:ip6Array]) {
        [hostObject setV6TTL:ttlInSecond];
        hostObject.lastIPv6LookupTime = [HttpdnsUtil currentEpochTimeInSecond];
    }

    [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
    if (![HttpdnsUtil isNotEmptyArray:ip6Array]) {
        HttpdnsLogDebug("Parsed host: %@ ttl: %lld ips: %@", [hostObject getHostName], [hostObject getTTL], ipArray);
    } else {
        HttpdnsLogDebug("Parsed host: %@ ttl: %lld ips: %@ ip6s: %@", [hostObject getHostName], [hostObject getTTL], ipArray, ip6Array);
    }
    return hostObject;
}

- (NSDictionary *)htmlEntityDecode:(NSString *)string {
    string = [string stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    string = [string stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    string = [string stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    string = [string stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    string = [string stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    string = [string stringByReplacingOccurrencesOfString:@"&nbsp" withString:@" "];
    string = [string stringByReplacingOccurrencesOfString:@"&mdash" withString:@"—"];
    string = [string stringByReplacingOccurrencesOfString:@"&hellip" withString:@"..."];
    string = [string stringByReplacingOccurrencesOfString:@"&rdquo" withString:@"”"];
    string = [string stringByReplacingOccurrencesOfString:@"&lsquo" withString:@"‘"];
    string = [string stringByReplacingOccurrencesOfString:@"&rsquo" withString:@"’"];
    string = [string stringByReplacingOccurrencesOfString:@"&ldquo" withString:@"“"];
    string = [string stringByReplacingOccurrencesOfString:@"&darr" withString:@"↓"];
    string = [string stringByReplacingOccurrencesOfString:@"&middot" withString:@"·"];
    NSData *jsonData = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&err];
    if (err) {
        return nil;
    }
    return dic;
}

- (NSString *)constructParamStr:(NSDictionary<NSString *, NSString *> *)params {
    NSString *str = @"^[A-Za-z0-9-_]+";
    NSPredicate *keyVerifyRegex = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", str];

    NSMutableArray *arr = [[NSMutableArray alloc] initWithCapacity:0];
    [params enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        if (![keyVerifyRegex evaluateWithObject:key]) {
            HttpdnsLogDebug("key string varification not passed, key: %@", key);
            return ;
        } else {
            NSString *str = [NSString stringWithFormat:@"%@%@", key, obj];
            if ([str lengthOfBytesUsingEncoding:NSUnicodeStringEncoding] > 1000) {
                HttpdnsLogDebug("sdns param key-value pair exceed length limitation, key: %@", key);
                return;
            } else {
                [arr addObject:[NSString stringWithFormat:@"sdns-%@=%@", key,obj]];
            }
        }
    }];

    return [arr componentsJoinedByString:@"&"];
}

- (NSString *)constructV6RequestURLWith:(HttpdnsRequest *)request {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    NSString *serverIp = [scheduleCenter currentActiveServiceServerV6Host];

    HttpDnsService *sharedService = [HttpDnsService sharedInstance];

    int accountId = sharedService.accountID;
    NSString *port = HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED ? ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT : ALICLOUD_HTTPDNS_HTTP_SERVER_PORT;

    NSString *url = [NSString stringWithFormat:@"%@:%@/%d/d?host=%@", serverIp, port, accountId, request.host];

    // sign
    NSString *secretKey = sharedService.secretKey;
    if ([HttpdnsUtil isNotEmptyString:secretKey]) {
        // 签名时间值需要使用10位整数秒值，因此这里需要转换
        long localTimestampOffset = (long)sharedService.authTimeOffset;
        long localTimestamp = (long)[[NSDate date] timeIntervalSince1970] ;
        if (localTimestampOffset != 0) {
            localTimestamp = localTimestamp + localTimestampOffset;
        }
        long expiredTimestamp = localTimestamp + HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL;
        NSString *expiredTimestampString = [NSString stringWithFormat:@"%@", @(expiredTimestamp)];
        NSString *signOriginString = [NSString stringWithFormat:@"%@-%@-%@", request.host, secretKey, expiredTimestampString];

        NSString *sign = [HttpdnsUtil getMD5StringFrom:signOriginString];
        NSString *signatureRequestString = [NSString stringWithFormat:@"t=%@&s=%@", expiredTimestampString, sign];

        url = [NSString stringWithFormat:@"%@:%@/%d/sign_d?host=%@&%@", serverIp, port, accountId, request.host, signatureRequestString];
    }

    // version
    NSString *versionInfo = [NSString stringWithFormat:@"ios_%@", HTTPDNS_IOS_SDK_VERSION];
    url = [NSString stringWithFormat:@"%@&sdk=%@", url, versionInfo];

    // sessionId
    NSString *sessionId = [HttpdnsUtil generateSessionID];
    if ([HttpdnsUtil isNotEmptyString:sessionId]) {
        url = [NSString stringWithFormat:@"%@&sid=%@", url, sessionId];
    }

    // sdns extra
    if ([HttpdnsUtil isNotEmptyDictionary:request.sdnsParams]) {
        NSString *sdnsParamStr = [self constructParamStr:request.sdnsParams];
        url = [NSString stringWithFormat:@"%@&%@", url, sdnsParamStr];
    }

    // 添加net和bssid(wifi)
    NSString *netType = [HttpdnsgetNetworkInfoHelper getNetworkType];
    if ([HttpdnsUtil isNotEmptyString:netType]) {
        url = [NSString stringWithFormat:@"%@&net=%@", url, netType];
        if ([HttpdnsgetNetworkInfoHelper isWifiNetwork]) {
            NSString *bssid = [HttpdnsgetNetworkInfoHelper getWifiBssid];
            if ([HttpdnsUtil isNotEmptyString:bssid]) {
                url = [NSString stringWithFormat:@"%@&bssid=%@", url, [EMASTools URLEncodedString:bssid]];
            }
        }
    }

    // 开启IPv6解析结果后，URL处理
    if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        url = [[HttpdnsIPv6Manager sharedInstance] appendQueryTypeToURL:url queryType:request.queryIpType];
    }

    return url;
}

- (NSString *)constructV4RequestURLWith:(HttpdnsRequest *)request useV4Ip:(bool *)useV4Ip {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];

    NSString *serverIp = nil;
    if ([[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork]) {
        serverIp = [scheduleCenter currentActiveServiceServerV6Host];
        *useV4Ip = NO;
    } else {
        serverIp = [scheduleCenter currentActiveServiceServerV4Host];
        *useV4Ip = YES;
    }

    HttpDnsService *sharedService = [HttpDnsService sharedInstance];

    int accountId = sharedService.accountID;
    NSString *port = HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED ? ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT : ALICLOUD_HTTPDNS_HTTP_SERVER_PORT;

    NSString *url = [NSString stringWithFormat:@"%@:%@/%d/d?host=%@", serverIp, port, accountId, request.host];

    // signature
    NSString *secretKey = sharedService.secretKey;
    if ([HttpdnsUtil isNotEmptyString:secretKey]) {
        // 签名时间值需要使用10位整数秒值，因此这里需要转换
        long localTimestampOffset = (long)sharedService.authTimeOffset;
        long localTimestamp = (long)[[NSDate date] timeIntervalSince1970] ;
        if (localTimestampOffset != 0) {
            localTimestamp = localTimestamp + localTimestampOffset;
        }
        long expiredTimestamp = localTimestamp + HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL;
        NSString *expiredTimestampString = [NSString stringWithFormat:@"%@", @(expiredTimestamp)];
        NSString *signOriginString = [NSString stringWithFormat:@"%@-%@-%@", request.host, secretKey, expiredTimestampString];

        NSString *sign = [HttpdnsUtil getMD5StringFrom:signOriginString];
        NSString *signatureRequestString = [NSString stringWithFormat:@"t=%@&s=%@", expiredTimestampString, sign];

        url = [NSString stringWithFormat:@"%@:%@/%d/sign_d?host=%@&%@",serverIp, port, accountId, request.host, signatureRequestString];
    }

    // version
    NSString *versionInfo = [NSString stringWithFormat:@"ios_%@", HTTPDNS_IOS_SDK_VERSION];
    url = [NSString stringWithFormat:@"%@&sdk=%@", url, versionInfo];

    // sessionId
    NSString *sessionId = [HttpdnsUtil generateSessionID];
    if ([HttpdnsUtil isNotEmptyString:sessionId]) {
        url = [NSString stringWithFormat:@"%@&sid=%@", url, sessionId];
    }

    // sdns extra
    if ([HttpdnsUtil isNotEmptyDictionary:request.sdnsParams]) {
        NSString *sdnsParamStr = [self constructParamStr:request.sdnsParams];
        url = [NSString stringWithFormat:@"%@&%@", url, sdnsParamStr];
    }

    // 添加net和bssid(wifi)
    NSString *netType = [HttpdnsgetNetworkInfoHelper getNetworkType];
    if ([HttpdnsUtil isNotEmptyString:netType]) {
        url = [NSString stringWithFormat:@"%@&net=%@", url, netType];
        if ([HttpdnsgetNetworkInfoHelper isWifiNetwork]) {
            NSString *bssid = [HttpdnsgetNetworkInfoHelper getWifiBssid];
            if ([HttpdnsUtil isNotEmptyString:bssid]) {
                url = [NSString stringWithFormat:@"%@&bssid=%@", url, [EMASTools URLEncodedString:bssid]];
            }
        }
    }

    // 开启IPv6解析结果后，URL处理
    if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        url = [[HttpdnsIPv6Manager sharedInstance] appendQueryTypeToURL:url queryType:request.queryIpType];
    }

    return url;
}

- (HttpdnsHostObject *)lookupHostFromServer:(HttpdnsRequest *)request error:(NSError **)error {
    [self resetRequestConfigure];

    HttpdnsLogDebug("lookupHostFromServer, request: %@", request);

    bool useV4ServerIp;
    NSString *url = [self constructV4RequestURLWith:request useV4Ip:&useV4ServerIp];

    if (![HttpdnsUtil isNotEmptyString:url]) {
        return nil;
    }

    HttpdnsQueryIPType queryIPType = request.queryIpType;
    NSString *host = request.host;

    HttpdnsHostObject *hostObject = nil;
    if (HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED) {
        hostObject = [self sendHTTPSRequest:url host:host error:error queryIpType:queryIPType];
    } else {
        // 为了走HTTP时不强依赖用户的ATS配置，这里走使用CFHTTP实现的网络请求方式
        hostObject = [self sendHTTPRequest:url host:host error:error queryIpType:queryIPType];
    }

    if (!(*error)) {
        return hostObject;
    }

    HttpdnsLogDebug("lookupHostFromServer failed, host: %@, error: %@", host, *error);

    NSError *outError = (*error);
    @try {
        // 请求出错，需要判断网络环境是否是双栈，如果是双栈，且之前是由v4地址请求的，则要由v6的serverIp做一次兜底
        AlicloudIPv6Adapter *ipv6Adapter = [AlicloudIPv6Adapter getInstance];
        AlicloudIPStackType stackType = [ipv6Adapter currentIpStackType];
        if (stackType == kAlicloudIPdual && useV4ServerIp) {
            url = [self constructV6RequestURLWith:request];
            HttpdnsLogDebug("lookupHostFromServer by ipv4 server failed, construct ipv6 backup url: %@", url);
            if ([HttpdnsUtil isNotEmptyString:url]) {
                NSError *backupError;
                if (HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED) {
                    hostObject = [self sendHTTPSRequest:url host:host error:&backupError queryIpType:queryIPType];
                } else {
                    hostObject = [self sendHTTPRequest:url host:host error:&backupError queryIpType:queryIPType];
                }
                if (backupError) {
                    outError = backupError;
                    *error = backupError;
                    HttpdnsLogDebug("lookupHostFromServer failed again by ipv6 server, error: %@", backupError);
                } else {
                    HttpdnsLogDebug("lookupHostFromServer success by ipv6 server, result: %@", hostObject);
                    *error = nil;
                }
            }
        }
    } @catch (NSException *exception) {
        HttpdnsLogDebug("lookupHostFromServer failed again by ipv6 server, exception: %@", exception.reason);
    }
    return hostObject;
}

- (HttpdnsHostObject *)sendHTTPSRequest:(NSString *)urlStr
                                   host:(NSString *)hostStr
                                  error:(NSError **)pError
                            queryIpType:(HttpdnsQueryIPType)queryIpType {
    NSString *fullUrlStr = [NSString stringWithFormat:@"https://%@", urlStr];
    HttpdnsLogDebug("HTTPS request URL: %@", fullUrlStr);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:fullUrlStr]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:[HttpDnsService sharedInstance].timeoutInterval];
    __block NSDictionary *json = nil;
    __block NSError *errorStrong = nil;
    __weak typeof(self) weakSelf = self;
    NSURLSessionTask *task = [_resolveHOSTSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            HttpdnsLogDebug("HTTPS request network error, host: %@, error: %@", hostStr, error);
            errorStrong = error;
        } else {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            HttpdnsLogDebug("Response code: %ld, body: %@", statusCode, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            if (statusCode == 200) {
                id jsonValue = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&errorStrong];
                if (!errorStrong) {
                    json = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
                }
            } else {
                errorStrong = [HttpdnsUtil getErrorFromError:errorStrong statusCode:statusCode json:json isHTTPS:YES];
            }
        }
        dispatch_semaphore_signal(strongSelf->_sem);
    }];
    [task resume];
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);
    if (!errorStrong) {
        return [self parseHostInfoFromHttpResponse:json withHostStr:hostStr withQueryIpType:queryIpType];
    }

    return nil;
}

- (HttpdnsHostObject *)sendHTTPRequest:(NSString *)urlStr
                                  host:(NSString *)host
                                 error:(NSError **)error
                           queryIpType:(HttpdnsQueryIPType)queryIpType {
    if (!error) {
        return nil;
    }
    if (![HttpdnsUtil isNotEmptyString:urlStr]) {
        return nil;
    }
    NSString *fullUrlStr = [NSString stringWithFormat:@"http://%@", urlStr];
    HttpdnsLogDebug("Resolve host via HTTP request, host: %@, fullUrl: %@", host, fullUrlStr);
    CFStringRef urlString = (__bridge CFStringRef)fullUrlStr;
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, urlString, NULL);
    CFStringRef requestMethod = CFSTR("GET");
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, url, kCFHTTPVersion1_1);
    CFReadStreamRef requestReadStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, request);
    _inputStream = (__bridge_transfer NSInputStream *)requestReadStream;

    NSThread *networkRequestThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkRequestThreadEntryPoint:) object:nil];
    [networkRequestThread start];

    CFRelease(url);
    CFRelease(request);
    CFRelease(requestMethod);
    request = NULL;

    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);

    *error = self.networkError;

    if (*error == nil && _httpJSONDict) {
        return [self parseHostInfoFromHttpResponse:_httpJSONDict withHostStr:host withQueryIpType:queryIpType];
    }
    return nil;
}

- (void)networkRequestThreadEntryPoint:(id)__unused object {
    @autoreleasepool {
        self.runloop = [NSRunLoop currentRunLoop];
        [self openInputStream];
        [self startTimer];
        /*
         *  通过调用[runloop run]; 开启线程的RunLoop时，引用苹果文档描述，"Manually removing all known input sources and timers from the run loop is not a guarantee that the run loop will exit. "，
         *  一定要手动停止RunLoop，CFRunLoopStop([runloop getCFRunLoop])；
         *  此处不再调用[runloop run]，改为[runloop runUtilDate:]，确保RunLoop正确退出。
         *  且NSRunLoop为非线程安全的。
         */
        [self.runloop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:([HttpDnsService sharedInstance].timeoutInterval + 5)]];
    }
}

- (void)openInputStream {
    [_inputStream setDelegate:self];
    [_inputStream scheduleInRunLoop:self.runloop forMode:NSRunLoopCommonModes];
    [_inputStream open];
}

- (void)closeInputStream {
    if (_inputStream) {
        [_inputStream close];
        [_inputStream removeFromRunLoop:self.runloop forMode:NSRunLoopCommonModes];
        [_inputStream setDelegate:nil];
        _inputStream = nil;
        CFRunLoopStop([self.runloop getCFRunLoop]);
    }
}

- (void)startTimer {
    if (!_timeoutTimer) {
        _timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:[HttpDnsService sharedInstance].timeoutInterval target:self selector:@selector(checkRequestStatus) userInfo:nil repeats:NO];
        [self.runloop addTimer:_timeoutTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)stopTimer {
    if (_timeoutTimer) {
        [_timeoutTimer invalidate];
        _timeoutTimer = nil;
    }
}

- (void)checkRequestStatus {
    [self stopTimer];
    [self closeInputStream];
    if (!_compeleted) {
        _compeleted = YES;
        NSDictionary *dic = [[NSDictionary alloc] initWithObjectsAndKeys:
                             @"Request timeout.", @"ErrorMessage", nil];
        self.networkError = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTP" code:ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE userInfo:dic];
        dispatch_semaphore_signal(_sem);
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable:{
            if (!_responseResolved) {
                CFReadStreamRef readStream = (__bridge CFReadStreamRef)_inputStream;
                CFHTTPMessageRef message = (CFHTTPMessageRef)CFReadStreamCopyProperty(readStream, kCFStreamPropertyHTTPResponseHeader);
                if (!message) {
                    return;
                }
                if (!CFHTTPMessageIsHeaderComplete(message)) {
                    HttpdnsLogDebug("Response not complete, continue.");
                    CFRelease(message);
                    return;
                }
                _responseResolved = YES;

                //先处理JSON
                CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(message);
                CFRelease(message);

                UInt8 buffer[16 * 1024];
                NSInteger numBytesRead = 0;
                // Read data
                if (!_resultData) {
                    _resultData = [NSMutableData data];
                }
                do {
                    numBytesRead = [_inputStream read:buffer maxLength:sizeof(buffer)];
                    if (numBytesRead > 0) {
                        [_resultData appendBytes:buffer length:numBytesRead];
                    }
                } while (numBytesRead > 0);

                NSDictionary *json;
                NSError *errorStrong = nil;
                if (_resultData) {
                    id jsonValue = [NSJSONSerialization JSONObjectWithData:_resultData options:kNilOptions error:&errorStrong];
                    json = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
                    _httpJSONDict = json;
                }
                HttpdnsLogDebug("Response code: %ld, body: %@", statusCode, [[NSString alloc] initWithData:_resultData encoding:NSUTF8StringEncoding]);
                if (statusCode != 200) {
                    errorStrong = [HttpdnsUtil getErrorFromError:errorStrong statusCode:statusCode json:json isHTTPS:NO];
                    self.networkError = errorStrong;
                    _compeleted = YES;
                    [self stopTimer];
                    [self closeInputStream];
                    dispatch_semaphore_signal(_sem);
                    return;
                }
            }
        }
            break;
        case NSStreamEventErrorOccurred:
        {
            NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  [NSString stringWithFormat:@"read stream error: %@", [aStream streamError].userInfo], @"ErrorMessage", nil];
            self.networkError = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTP" code:ALICLOUD_HTTPDNS_HTTP_STREAM_READ_ERROR_CODE userInfo:dict];
        }
        case NSStreamEventEndEncountered:
            [self stopTimer];
            [self closeInputStream];
            _compeleted = YES;
            dispatch_semaphore_signal(_sem);
            break;
        default:
            break;
    }
}

- (HttpdnsRequestScheduler *)requestScheduler {
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    return sharedService.requestScheduler;
}

#pragma mark - NSURLSessionTaskDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *_Nullable))completionHandler {
    if (!challenge) {
        return;
    }
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;
    NSString *host = ALICLOUD_HTTPDNS_VALID_SERVER_CERTIFICATE_IP;
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:host]) {
            disposition = NSURLSessionAuthChallengeUseCredential;
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    } else {
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    }
    completionHandler(disposition, credential);
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain {
    NSMutableArray *policies = [NSMutableArray array];
    if (domain) {
        [policies addObject:(__bridge_transfer id) SecPolicyCreateSSL(true, (__bridge CFStringRef) domain)];
    } else {
        [policies addObject:(__bridge_transfer id) SecPolicyCreateBasicX509()];
    }
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef) policies);
    SecTrustResultType result;
    SecTrustEvaluate(serverTrust, &result);
    if (result == kSecTrustResultRecoverableTrustFailure) {
        CFDataRef errDataRef = SecTrustCopyExceptions(serverTrust);
        SecTrustSetExceptions(serverTrust, errDataRef);
        SecTrustEvaluate(serverTrust, &result);
    }
    return (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}

@end

