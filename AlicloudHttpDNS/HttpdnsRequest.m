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
#import "HttpdnsLog.h"
#import "HttpdnsConfig.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsConstants.h"
#import "AlicloudHttpDNS.h"

NSInteger const ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE = 10005;
NSInteger const ALICLOUD_HTTPDNS_HTTP_STREAM_READ_ERROR_CODE = 10006;
NSInteger const ALICLOUD_HTTPDNS_HTTPS_TIMEOUT_ERROR_CODE = -1001;
NSInteger const ALICLOUD_HTTPDNS_HTTP_CANNOT_CONNECT_SERVER_ERROR_CODE = -1004;
NSInteger const ALICLOUD_HTTPDNS_HTTP_USER_LEVEL_CHANGED_ERROR_CODE = 403;

NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_KEY = @"activated_IP_index_key";
NSString *const ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED_INDEX_CACHE_FILE_NAME = @"activated_IP_index";

static NSURLSession *_resolveHOSTSession = nil;

@interface HttpdnsRequest () <NSStreamDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@end

@implementation HttpdnsRequest
{
    NSMutableData *_resultData;
    dispatch_semaphore_t _sem;
    NSRunLoop *_runloop;
    NSInputStream *_inputStream;
    NSError *_networkError;
    BOOL _responseResolved;
    BOOL _compeleted;
    NSTimer *_timeoutTimer;
}

#pragma mark init

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
    _networkError = nil;
    _responseResolved = NO;
    _compeleted = NO;
}

#pragma mark LookupIpAction

- (HttpdnsHostObject *)parseHostInfoFromHttpResponse:(NSDictionary *)json {
    if (json == nil) {
        return nil;
    }
    NSString *hostName = [json objectForKey:@"host"];
    NSArray *ips = [json objectForKey:@"ips"];
    if (ips == nil || [ips count] == 0) {
        HttpdnsLogDebug("IP list is empty for host %@", hostName);
        return nil;
    }
    NSMutableArray *ipArray = [[NSMutableArray alloc] init];
    for (NSString *ip in ips) {
        HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
        // Adapt to IPv6-only network.
        [ipObject setIp:[[AlicloudIPv6Adapter getInstance] handleIpv4Address:ip]];
        [ipArray addObject:ipObject];
    }
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    [hostObject setHostName:hostName];
    [hostObject setIps:ipArray];
    [hostObject setTTL:[[json objectForKey:@"ttl"] longLongValue]];
    [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
    [hostObject setQueryingState:NO];
    HttpdnsLogDebug("Parsed host: %@ ttl: %lld ips: %@", [hostObject getHostName], [hostObject getTTL], ipArray);
    return hostObject;
}

- (NSString *)constructRequestURLWith:(NSString *)hostsString activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    NSString *serverIp = [scheduleCenter getActivatedServerIPWithIndex:activatedServerIPIndex];

    // Adapt to IPv6-only network.
    if ([[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork]) {
        serverIp = [NSString stringWithFormat:@"[%@]", [[AlicloudIPv6Adapter getInstance] handleIpv4Address:serverIp]];
    }
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSString *versionInfo = [NSString stringWithFormat:@"ios_%@",HTTPDNS_IOS_SDK_VERSION];
    NSString *port = HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED ? ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT : ALICLOUD_HTTPDNS_HTTP_SERVER_PORT;
    NSString *url = [NSString stringWithFormat:@"%@:%@/%d/d?host=%@&sdk=%@",
                     serverIp, port, sharedService.accountID, hostsString, versionInfo];
    return url;
}

- (HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
   return [self lookupHostFromServer:hostString error:error activatedServerIPIndex:scheduleCenter.activatedServerIPIndex];
}

- (HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    [self resetRequestConfigure];
    HttpdnsLogDebug("Resolve host(%@) over network.", hostString);
    NSString *url = [self constructRequestURLWith:hostString activatedServerIPIndex:activatedServerIPIndex];
    if (HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED) {
        return [self sendHTTPSRequest:url error:error activatedServerIPIndex:activatedServerIPIndex];
    } else {
        return [self sendHTTPRequest:url error:error activatedServerIPIndex:activatedServerIPIndex];
    }
    return nil;
}

//TODO:携带SDK版本 http://gitlab.alibaba-inc.com/alicloud-ams/httpdns-doc/blob/master/api/param_sdk.md
// 基于URLSession发送HTTPS请求
- (HttpdnsHostObject *)sendHTTPSRequest:(NSString *)urlStr
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
            json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&errorStrong];
            NSInteger statusCode = [(NSHTTPURLResponse *) response statusCode];
            if (statusCode != 200) {
                HttpdnsLogDebug("ReponseCode %ld.", (long)statusCode);
                if (errorStrong) {
                    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                          @"Response code not 200, and parse response message error", ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY,
                                          [NSString stringWithFormat:@"%ld", (long)statusCode], @"ResponseCode", nil];
                    errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10002 userInfo:dict];
                } else {
                    NSString *errCode = [json objectForKey:@"code"];
                    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                          errCode, ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY, nil];
                    errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10003 userInfo:dict];
                }
            } else {
                HttpdnsLogDebug("Response code 200.");
            }
        }
        dispatch_semaphore_signal(_sem);
    }];
    [task resume];
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);
    
    if (!errorStrong) {
        return [self parseHostInfoFromHttpResponse:json];
    }
    
    if (pError != NULL) {
        *pError = errorStrong;        
        [self.requestScheduler changeToNextServerIPIfNeededWithError:errorStrong
                                                         fromIPIndex:activatedServerIPIndex
                                                             isHTTPS:YES];
    }
    return nil;
}

// 基于CFNetwork发送HTTP请求
- (HttpdnsHostObject *)sendHTTPRequest:(NSString *)urlStr
                                 error:(NSError **)error
 activatedServerIPIndex:(NSInteger)activatedServerIPIndex {
    if (!error) {
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
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        _runloop = [NSRunLoop currentRunLoop];
        [self openInputStream];
        [self startTimer];
        /*
         *  通过调用[runloop run]; 开启线程的RunLoop时，引用苹果文档描述，"Manually removing all known input sources and timers from the run loop is not a guarantee that the run loop will exit. "，
         *  一定要手动停止RunLoop，CFRunLoopStop([runloop getCFRunLoop])；
         *  此处不再调用[runloop run]，改为[runloop runUtilDate:]，确保RunLoop正确退出。
         *  且NSRunLoop为非线程安全的。
         */
        [_runloop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:([HttpDnsService sharedInstance].timeoutInterval + 5)]];
    });
    
    CFRelease(url);
    CFRelease(request);
    CFRelease(requestMethod);
    request = NULL;
    
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);
    
    *error = _networkError;
    
    [self.requestScheduler changeToNextServerIPIfNeededWithError:_networkError
                                                     fromIPIndex:activatedServerIPIndex
                                                         isHTTPS:NO];
    
    NSDictionary *json;
    if (*error == nil) {
        json = [NSJSONSerialization JSONObjectWithData:_resultData options:kNilOptions error:error];
    }
    
    if (json) {
        return [self parseHostInfoFromHttpResponse:json];
    }
    return nil;
}

- (void)openInputStream {
    // 防止循环引用
    __weak typeof(self) weakSelf = self;
    [_inputStream setDelegate:weakSelf];
    [_inputStream scheduleInRunLoop:_runloop forMode:NSRunLoopCommonModes];
    [_inputStream open];
}

- (void)closeInputStream {
    if (_inputStream) {
        [_inputStream close];
        [_inputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
        [_inputStream setDelegate:nil];
        _inputStream = nil;
        CFRunLoopStop([_runloop getCFRunLoop]);
    }
}

- (void)startTimer {
    if (!_timeoutTimer) {
        _timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:[HttpDnsService sharedInstance].timeoutInterval target:self selector:@selector(checkRequestStatus) userInfo:nil repeats:NO];
        [_runloop addTimer:_timeoutTimer forMode:NSRunLoopCommonModes];
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
                             @"Request timeout.", ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY, nil];
        _networkError = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTP" code:ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE userInfo:dic];
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
                CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(message);
                CFRelease(message);
                if (statusCode != 200) {
                    //403错误需要强制更新SC
                    NSString *errorMessage;
                    if (statusCode == 403) {
                        errorMessage = ALICLOUD_HTTPDNS_ERROR_SERVICE_LEVEL_DENY;
                    } else {
                        errorMessage = @"status code not 200";
                    }
                    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                          errorMessage, ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY, nil];
                    _networkError = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTP" code:10004 userInfo:dict];
                    _compeleted = YES;
                    [self stopTimer];
                    [self closeInputStream];
                    dispatch_semaphore_signal(_sem);
                    return;
                }
                HttpdnsLogDebug("Response code 200.");
            }
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
        }
            break;
        case NSStreamEventErrorOccurred:
        {
            NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  [NSString stringWithFormat:@"read stream error: %@", [aStream streamError].userInfo], ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY, nil];
            _networkError = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTP" code:ALICLOUD_HTTPDNS_HTTP_STREAM_READ_ERROR_CODE userInfo:dict];
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
    NSString *host = ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED;
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
    return (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}

@end

