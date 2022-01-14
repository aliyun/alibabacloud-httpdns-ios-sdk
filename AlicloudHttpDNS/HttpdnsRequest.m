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

#import "HttpdnsServiceProvider.h"
#import "HttpdnsModel.h"
#import "HttpdnsRequest.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsConfig.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsConstants.h"
#import "AlicloudHttpDNS.h"
#import "HttpDnsHitService.h"
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

@interface HttpdnsRequest () <NSStreamDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) NSRunLoop *runloop;
@property (nonatomic, strong) NSError *networkError;

//记录域名解析发生时，当前service ip的region
@property (nonatomic, copy) NSString *serviceRegion;


@end

@implementation HttpdnsRequest
{
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

- (HttpdnsHostObject *)parseHostInfoFromHttpResponse:(NSDictionary *)json withHostStr:(NSString *)hostStr {
    if (json == nil) {
        return nil;
    }    
    NSString *hostName;
    NSArray *ips;
    NSArray *ip6s;
    NSDictionary *extra;
    NSArray *hostArray= [hostStr componentsSeparatedByString:@"]"];
    hostStr = [hostArray lastObject];
    if ([[json allKeys] containsObject:@"extra"]) {
        extra = [self htmlEntityDecode:[HttpdnsUtil safeObjectForKey:@"extra" dict:json]];
    }
    hostName = hostStr;
    ips = [HttpdnsUtil safeObjectForKey:@"ips" dict:json];
    ip6s = [HttpdnsUtil safeObjectForKey:@"ipsv6" dict:json];
    if ((![HttpdnsUtil isValidArray:ips] && ![HttpdnsUtil isValidArray:ip6s]) || ![HttpdnsUtil isValidString:hostName]) {
        HttpdnsHostObject *cacheHostObject = [self.requestScheduler hostObjectFromCacheForHostName:hostStr];
        if (cacheHostObject) {
            [cacheHostObject setQueryingState:NO];
        }
        HttpdnsLogDebug("IP list is empty for host %@", hostName);
        return nil;
    }
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    
    //处理ipv4
    NSMutableArray *ipArray = [NSMutableArray array];
    for (NSString *ip in ips) {
        if (![HttpdnsUtil isValidString:ip]) {
            continue;
        }
        HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
        // 用户主动开启v6解析后，IPv6-Only场景解析结果不再自动适配
        // 确保getIpByHostAsync()返回v4地址，getIp6ByHostAsync()返回v6地址
        if (![[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
            [ipObject setIp:[[AlicloudIPv6Adapter getInstance] handleIpv4Address:ip]];
        } else {
            [ipObject setIp:ip];
        }
        [ipArray addObject:ipObject];
    }
    
    // 处理IPv6解析结果
    NSMutableArray *ip6Array = [NSMutableArray array];
    if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        for (NSString *ipv6 in ip6s) {
            if (![EMASTools isValidString:ipv6]) {
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
    [hostObject setHostName:hostName];
    [hostObject setIps:ipArray];
    [hostObject setIp6s:ip6Array];
    [hostObject setTTL:[[json objectForKey:@"ttl"] longLongValue]];
    
    //分别设置 v4ttl v6ttl
    if ([HttpdnsUtil isValidArray:ipArray]) {
        [hostObject setV4TTL:[[json objectForKey:@"ttl"] longLongValue]];
        hostObject.lastIPv4LookupTime = [HttpdnsUtil currentEpochTimeInSecond];
        hostObject.ipRegion = self.serviceRegion;
    }
    if ([HttpdnsUtil isValidArray:ip6Array]) {
        [hostObject setV6TTL:[[json objectForKey:@"ttl"] longLongValue]];
        hostObject.lastIPv6LookupTime = [HttpdnsUtil currentEpochTimeInSecond];
        hostObject.ip6Region = self.serviceRegion;
    }
    
    
    [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
    [hostObject setQueryingState:NO];
    if (![EMASTools isValidArray:ip6Array]) {
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
    if(err) {
        return nil;
    }
    return dic;
}

- (NSString *)constructRequestURLWith:(NSString *)hostsString activatedServerIPIndex:(NSInteger)activatedServerIPIndex reallyHostKey:(NSString *)reallyHostKey queryIPType:(HttpdnsQueryIPType)queryIPType {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    NSString *serverIp = [scheduleCenter getActivatedServerIPWithIndex:activatedServerIPIndex];
    self.serviceRegion = [scheduleCenter getServiceIPRegion]; //获取当前service IP 的region
    
    if ([EMASTools isValidString:self.serviceRegion] && [@[ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED, ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP, ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP_2] containsObject:serverIp]) { //如果当前设置region 并且 当次服务IP是国内兜底IP 则直接禁止解析行为
        return nil;
    }
    
    // Adapt to IPv6-only network.
    if ([[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork]) {
        serverIp = [NSString stringWithFormat:@"[%@]", [[AlicloudIPv6Adapter getInstance] handleIpv4Address:serverIp]];
    }
    NSString *requestType = @"d";
    NSString *signatureRequestString = nil;
    
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];

    NSString *secretKey = sharedService.secretKey;
    NSUInteger localTimestampOffset = sharedService.authTimeOffset;
    if ([HttpdnsUtil isValidString:secretKey ]) {
        requestType = @"sign_d";
        NSUInteger localTimestamp = (NSUInteger)[[NSDate date] timeIntervalSince1970] ;
        if (localTimestampOffset != 0) {
            localTimestamp = localTimestamp + localTimestampOffset;
        }
        NSUInteger expiredTimestamp = localTimestamp + HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL;
        NSString *expiredTimestampString = [NSString stringWithFormat:@"%@", @(expiredTimestamp)];
        NSArray *hostArray= [hostsString componentsSeparatedByString:@"&"];
        NSString *hostStr = [hostArray firstObject];
        NSString *signOriginString = [NSString stringWithFormat:@"%@-%@-%@", hostStr, secretKey, expiredTimestampString];
        
        NSString *sign = [HttpdnsUtil getMD5StringFrom:signOriginString];
        signatureRequestString = [NSString stringWithFormat:@"&t=%@&s=%@", expiredTimestampString, sign];
    }
    
    NSString *port = HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED ? ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT : ALICLOUD_HTTPDNS_HTTP_SERVER_PORT;
    
    NSString *url = [NSString stringWithFormat:@"%@:%@/%d/%@?host=%@",
                     serverIp, port, sharedService.accountID, requestType, hostsString];
    
    if ([HttpdnsUtil isValidString:signatureRequestString]) {
        url = [NSString stringWithFormat:@"%@%@", url, signatureRequestString];
    }
    NSString *versionInfo = [NSString stringWithFormat:@"ios_%@", HTTPDNS_IOS_SDK_VERSION];
    url = [NSString stringWithFormat:@"%@&sdk=%@", url, versionInfo];
    
    // sessionId
    NSString *sessionId = [HttpdnsUtil generateSessionID];
    if ([HttpdnsUtil isValidString:sessionId]) {
        url = [NSString stringWithFormat:@"%@&sid=%@", url, sessionId];
    }
    
    // 添加net和bssid(wifi)
    NSString *netType = [HttpdnsgetNetworkInfoHelper getNetworkType];
    if ([HttpdnsUtil isValidString:netType]) {
        url = [NSString stringWithFormat:@"%@&net=%@", url, netType];
        if ([HttpdnsgetNetworkInfoHelper isWifiNetwork]) {
            NSString *bssid = [HttpdnsgetNetworkInfoHelper getWifiBssid];
            if ([HttpdnsUtil isValidString:bssid]) {
                url = [NSString stringWithFormat:@"%@&bssid=%@", url, [EMASTools URLEncodedString:bssid]];
            }
        }
    }
    
    // 开启IPv6解析结果后，URL处理
    if ([[HttpdnsIPv6Manager sharedInstance] isAbleToResolveIPv6Result]) {
        //设置当前域名的查询策略
        [[HttpdnsIPv6Manager sharedInstance] setQueryHost:reallyHostKey ipQueryType:queryIPType];
        
        url = [[HttpdnsIPv6Manager sharedInstance] assembleIPv6ResultURL:url queryHost:reallyHostKey];
    }
    
    return url;
}

- (HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    return [self lookupHostFromServer:hostString error:error activatedServerIPIndex:scheduleCenter.activatedServerIPIndex queryIPType:HttpdnsQueryIPTypeIpv4];
}

- (HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error activatedServerIPIndex:(NSInteger)activatedServerIPIndex queryIPType:(HttpdnsQueryIPType)queryIPType{
    // 配置设置
    [self resetRequestConfigure];
    // 解析主机
    HttpdnsLogDebug("\n ====== Resolve host(%@) over network.", hostString);
    HttpdnsHostObject *hostObject = nil;
    
    NSString *copyHostString = hostString;
    NSArray *hostArray= [hostString componentsSeparatedByString:@"]"];
    hostString = [hostArray lastObject];
    NSMutableArray * hostMArray = [NSMutableArray arrayWithArray:hostArray];
    if (hostMArray.count == 3) {
        [hostMArray removeLastObject];
    }
    NSString * hostsUrl = [hostMArray componentsJoinedByString:@""];
    NSString *url = [self constructRequestURLWith:hostsUrl activatedServerIPIndex:activatedServerIPIndex reallyHostKey:hostString queryIPType:queryIPType];
    
    if (![EMASTools isValidString:url]) {
        return nil;
    }
    
    // HTTP / HTTPS  请求
    if (HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED) {
        hostObject = [self sendHTTPSRequest:url host:copyHostString error:error activatedServerIPIndex:activatedServerIPIndex];
    } else {
        hostObject = [self sendHTTPRequest:url host:copyHostString error:error activatedServerIPIndex:activatedServerIPIndex];
    }
    
    NSError *outError = nil;
    if (error != NULL) {
        outError = (*error);
    }
    BOOL success = !outError;
    BOOL cachedIPEnabled = [self.requestScheduler _getCachedIPEnabled];
    [HttpDnsHitService bizPerfGetIPWithHost:hostString success:success cacheOpen:cachedIPEnabled];
    return hostObject;
}

- (HttpdnsHostObject *)sendHTTPSRequest:(NSString *)urlStr
                                   host:(NSString *)hostStr
                                  error:(NSError **)pError
                 activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    NSString *fullUrlStr = [NSString stringWithFormat:@"https://%@", urlStr];
    HttpdnsLogDebug("Request URL: %@", fullUrlStr);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:fullUrlStr]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:[HttpDnsService sharedInstance].timeoutInterval];
    __block NSDictionary *json = nil;
    __block NSError *errorStrong = nil;
    NSURLSessionTask *task = [_resolveHOSTSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            HttpdnsLogDebug("Network error: %@", error);
            errorStrong = error;
        } else {
            id jsonValue = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&errorStrong];
            json = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
            NSInteger statusCode = [(NSHTTPURLResponse *) response statusCode];
            errorStrong = [HttpdnsUtil getErrorFromError:errorStrong statusCode:statusCode json:json isHTTPS:YES];
        }
        dispatch_semaphore_signal(_sem);
    }];
    [task resume];
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);
    if (!errorStrong) {
        return [self parseHostInfoFromHttpResponse:json withHostStr:hostStr];
    }
    
    if (pError != NULL) {
        *pError = errorStrong;
        [self.requestScheduler changeToNextServerIPIfNeededWithError:errorStrong
                                                         fromIPIndex:activatedServerIPIndex
                                                             isHTTPS:YES];
    }
    return nil;
}

- (HttpdnsHostObject *)sendHTTPRequest:(NSString *)urlStr
                                  host:(NSString *)hostStr
                                 error:(NSError **)error
 activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    if (!error) {
        return nil;
    }
    if (![HttpdnsUtil isValidString:urlStr]) {
        return nil;
    }
    NSString *fullUrlStr = [NSString stringWithFormat:@"http://%@", urlStr];
    HttpdnsLogDebug("Request URL: %@", fullUrlStr);
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
    NSDate *methodStart = [NSDate date];
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);
    *error = self.networkError;
    if (!self.networkError) {
        [HttpDnsHitService hitSRVTimeWithSuccess:YES methodStart:methodStart url:fullUrlStr];
    }
    [self.requestScheduler changeToNextServerIPIfNeededWithError:self.networkError
                                                     fromIPIndex:activatedServerIPIndex
                                                         isHTTPS:NO];
    if (*error == nil && _httpJSONDict) {
        return [self parseHostInfoFromHttpResponse:_httpJSONDict withHostStr:hostStr];
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
                if (statusCode != 200) {
                    errorStrong = [HttpdnsUtil getErrorFromError:errorStrong statusCode:statusCode json:json isHTTPS:NO];
                    self.networkError = errorStrong;
                    _compeleted = YES;
                    [self stopTimer];
                    [self closeInputStream];
                    dispatch_semaphore_signal(_sem);
                    return;
                }
                HttpdnsLogDebug("Response code 200.");
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

