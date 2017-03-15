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

#ifdef DEBUG
NSString * const ALICLOUD_HTTPDNS_SERVER_IP = @"10.125.65.207";
NSString * const ALICLOUD_HTTPDNS_HTTP_SERVER_PORT = @"8100";
NSString * const ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT = @"8100";
#else
NSString * const ALICLOUD_HTTPDNS_SERVER_IP = @"203.107.1.1";
NSString * const ALICLOUD_HTTPDNS_HTTP_SERVER_PORT = @"80";
NSString * const ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT = @"443";
#endif

@interface HttpdnsRequest () <NSStreamDelegate>

@end

@implementation HttpdnsRequest
{
    NSMutableData *resultData;
    dispatch_semaphore_t sem;
    NSRunLoop *runloop;
    NSInputStream *inputStream;
    NSError *networkError;
    BOOL responseResolved;
    BOOL compeleted;
    NSTimer *timeoutTimer;
}

#pragma mark init

- (instancetype)init {
    if (self = [super init]) {
        resultData = [NSMutableData data];
        sem = dispatch_semaphore_create(0);
        networkError = nil;
        responseResolved = NO;
        compeleted = NO;
    }
    return self;
}

#pragma mark LookupIpAction

-(HttpdnsHostObject *)parseHostInfoFromHttpResponse:(NSDictionary *)json {
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

-(NSString *)constructRequestURLWith:(NSString *)hostsString {
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSString *serverIp = ALICLOUD_HTTPDNS_SERVER_IP;
    // Adapt to IPv6-only network.
    if ([[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork]) {
        serverIp = [NSString stringWithFormat:@"[%@]", [[AlicloudIPv6Adapter getInstance] handleIpv4Address:ALICLOUD_HTTPDNS_SERVER_IP]];
    }
    NSString *port = HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED ? ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT : ALICLOUD_HTTPDNS_HTTP_SERVER_PORT;
    NSString *url = [NSString stringWithFormat:@"%@:%@/%d/d?host=%@",
                     serverIp, port, sharedService.accountID, hostsString];
    return url;
}

-(HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error {
    HttpdnsLogDebug("Resolve host(%@) over network.", hostString);
    NSString *url = [self constructRequestURLWith:hostString];
    if (HTTPDNS_REQUEST_PROTOCOL_HTTPS_ENABLED) {
        return [self sendHTTPSRequest:url error:error];
    } else {
        return [self sendHTTPRequest:url error:error];
    }
    return nil;
}

// 基于URLSession发送HTTPS请求
- (HttpdnsHostObject *)sendHTTPSRequest:(NSString *)urlStr error:(NSError **)pError {
    NSString *fullUrlStr = [NSString stringWithFormat:@"https://%@", urlStr];
    HttpdnsLogDebug("Request URL: %@", fullUrlStr);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:fullUrlStr]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:[HttpDnsService sharedInstance].timeoutInterval];
    __block NSDictionary *json = nil;
    __block NSError *errorStrong = nil;
    NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
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
                                          @"Response code not 200, and parse response message error", @"ErrorMessage",
                                          [NSString stringWithFormat:@"%ld", (long)statusCode], @"ResponseCode", nil];
                    errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10002 userInfo:dict];
                } else {
                    NSString *errCode = [json objectForKey:@"code"];
                    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                          errCode, @"ErrorMessage", nil];
                    errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10003 userInfo:dict];
                }
            } else {
                HttpdnsLogDebug("Response code 200.");
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    
    if (!errorStrong) {
        return [self parseHostInfoFromHttpResponse:json];
    }
    
    if (pError != NULL && errorStrong) {
        *pError = errorStrong;
    }
    return nil;
}

// 基于CFNetwork发送HTTP请求
- (HttpdnsHostObject *)sendHTTPRequest:(NSString *)urlStr error:(NSError **)error {
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
    inputStream = (__bridge_transfer NSInputStream *)requestReadStream;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        runloop = [NSRunLoop currentRunLoop];
        [self openInputStream];
        [self startTimer];
        /*
         *  通过调用[runloop run]; 开启线程的RunLoop时，引用苹果文档描述，"Manually removing all known input sources and timers from the run loop is not a guarantee that the run loop will exit. "，
         *  一定要手动停止RunLoop，CFRunLoopStop([runloop getCFRunLoop])；
         *  此处不再调用[runloop run]，改为[runloop runUtilDate:]，确保RunLoop正确退出。
         *  且NSRunLoop为非线程安全的。
         */
        [runloop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:([HttpDnsService sharedInstance].timeoutInterval + 5)]];
    });
    
    CFRelease(url);
    CFRelease(request);
    CFRelease(requestMethod);
    request = NULL;
    
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    
    *error = networkError;
    NSDictionary *json;
    if (*error == nil) {
        json = [NSJSONSerialization JSONObjectWithData:resultData options:kNilOptions error:error];
    }
    
    if (*error == nil) {
        return [self parseHostInfoFromHttpResponse:json];
    }
    return nil;
}

- (void)openInputStream {
    // 防止循环引用
    __weak typeof(self) weakSelf = self;
    [inputStream setDelegate:weakSelf];
    [inputStream scheduleInRunLoop:runloop forMode:NSRunLoopCommonModes];
    [inputStream open];
}

- (void)closeInputStream {
    if (inputStream) {
        [inputStream close];
        [inputStream removeFromRunLoop:runloop forMode:NSRunLoopCommonModes];
        [inputStream setDelegate:nil];
        inputStream = nil;
        CFRunLoopStop([runloop getCFRunLoop]);
    }
}

- (void)startTimer {
    if (!timeoutTimer) {
        timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:[HttpDnsService sharedInstance].timeoutInterval target:self selector:@selector(checkRequestStatus) userInfo:nil repeats:NO];
        [runloop addTimer:timeoutTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)stopTimer {
    if (timeoutTimer) {
        [timeoutTimer invalidate];
        timeoutTimer = nil;
    }
}

- (void)checkRequestStatus {
    [self stopTimer];
    [self closeInputStream];
    if (!compeleted) {
        compeleted = YES;
        NSDictionary *dic = [[NSDictionary alloc] initWithObjectsAndKeys:
                             @"Request timeout.", @"ErrorMessage", nil];
        networkError = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTP" code:10005 userInfo:dic];
        dispatch_semaphore_signal(sem);
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable:{
            if (!responseResolved) {
                CFReadStreamRef readStream = (__bridge CFReadStreamRef)inputStream;
                CFHTTPMessageRef message = (CFHTTPMessageRef)CFReadStreamCopyProperty(readStream, kCFStreamPropertyHTTPResponseHeader);
                if (!message) {
                    return;
                }
                if (!CFHTTPMessageIsHeaderComplete(message)) {
                    HttpdnsLogDebug("Response not complete, continue.");
                    CFRelease(message);
                    return;
                }
                responseResolved = YES;
                CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(message);
                CFRelease(message);
                if (statusCode != 200) {
                    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                          @"status code not 200", @"ErrorMessage", nil];
                    networkError = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTP" code:10004 userInfo:dict];
                    compeleted = YES;
                    [self stopTimer];
                    [self closeInputStream];
                    dispatch_semaphore_signal(sem);
                    return;
                }
                HttpdnsLogDebug("Response code 200.");
            }
            UInt8 buffer[16 * 1024];
            NSInteger numBytesRead = 0;
            // Read data
            if (!resultData) {
                resultData = [NSMutableData data];
            }
            do {
                numBytesRead = [inputStream read:buffer maxLength:sizeof(buffer)];
                if (numBytesRead > 0) {
                    [resultData appendBytes:buffer length:numBytesRead];
                }
            } while (numBytesRead > 0);
        }
            break;
        case NSStreamEventErrorOccurred:
        {
            NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  [NSString stringWithFormat:@"read stream error: %@", [aStream streamError].userInfo], @"ErrorMessage", nil];
            networkError = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTP" code:10006 userInfo:dict];
        }
        case NSStreamEventEndEncountered:
            [self stopTimer];
            [self closeInputStream];
            compeleted = YES;
            dispatch_semaphore_signal(sem);
            break;
        default:
            break;
    }
}

@end
