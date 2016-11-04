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

@implementation HttpdnsRequest

#pragma mark init

-(instancetype)init {
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
    NSString *port = REQUEST_PROTOCOL_HTTPS_ENABLED ? ALICLOUD_HTTPDNS_HTTPS_SERVER_PORT : ALICLOUD_HTTPDNS_HTTP_SERVER_PORT;
    NSString *url = [NSString stringWithFormat:@"%@:%@/%d/d?host=%@",
                     serverIp, port, sharedService.accountID, hostsString];
    return url;
}

-(HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error {
    HttpdnsLogDebug("Resolve host(%@) over network.", hostString);
    NSString *url = [self constructRequestURLWith:hostString];
    if (REQUEST_PROTOCOL_HTTPS_ENABLED) {
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
                                                       timeoutInterval:REQUEST_TIMEOUT_INTERVAL];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSDictionary *json;
    NSURLSessionTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            HttpdnsLogDebug("Network error: %@", error);
            *pError = error;
        } else {
            json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:pError];
            NSInteger statusCode = [(NSHTTPURLResponse *) response statusCode];
            if (statusCode != 200) {
                HttpdnsLogDebug("ReponseCode %ld.", (long)statusCode);
                if (*pError) {
                    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                          @"Response code not 200, and parse response message error", @"ErrorMessage",
                                          [NSString stringWithFormat:@"%ld", (long)statusCode], @"ResponseCode", nil];
                    *pError = [[NSError alloc] initWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10002 userInfo:dict];
                } else {
                    NSString *errCode = [json objectForKey:@"code"];
                    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                          errCode, @"ErrorMessage", nil];
                    *pError = [[NSError alloc] initWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10003 userInfo:dict];
                }
            } else {
                HttpdnsLogDebug("Response code 200.");
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (*pError == nil) {
        return [self parseHostInfoFromHttpResponse:json];
    }
    return nil;
}

// 基于CFNetwork发送HTTP请求
- (HttpdnsHostObject *)sendHTTPRequest:(NSString *)urlStr error:(NSError **)error {
    NSString *fullUrlStr = [NSString stringWithFormat:@"http://%@", urlStr];
    HttpdnsLogDebug("Request URL: %@", fullUrlStr);
    CFStringRef urlString = (__bridge CFStringRef)fullUrlStr;
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, urlString, NULL);
    CFStringRef requestMethod = CFSTR("GET");
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, url, kCFHTTPVersion1_1);
    CFReadStreamRef requestReadStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, request);
    
    NSDictionary *json;
    if (CFReadStreamOpen(requestReadStream) == NO) {
        CFStreamError err = CFReadStreamGetError(requestReadStream);
        if (err.error != 0) {
            *error = [NSError errorWithDomain:@"CFStreamErrorDomain" code:err.error userInfo:nil];
        } else {
            *error = [NSError errorWithDomain:@"UnknownCFStreamErrorDomain" code:0 userInfo:nil];
        }
    } else {
        CFHTTPMessageRef response = (CFHTTPMessageRef)CFReadStreamCopyProperty(requestReadStream, kCFStreamPropertyHTTPResponseHeader);
        CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(response);
        if (statusCode != 200) {
            HttpdnsLogDebug("ReponseCode %ld.", (long)statusCode);
            NSString *errCode = [json objectForKey:@"code"];
            NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  errCode, @"ErrorMessage", nil];
            *error = [[NSError alloc] initWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10003 userInfo:dict];
        } else {
            HttpdnsLogDebug("Response code 200.");
            UInt8 buf[1024];
            CFIndex numBytesRead;
            NSMutableData *resultData = [NSMutableData data];
            do {
                numBytesRead = CFReadStreamRead(requestReadStream, buf, sizeof(buf));
                if ( numBytesRead > 0 ) {
                    [resultData appendBytes:buf length:numBytesRead];
                }
            } while( numBytesRead > 0 );
            json = [NSJSONSerialization JSONObjectWithData:resultData options:kNilOptions error:error];
        }
    }
    
    CFRelease(url);
    CFRelease(request);
    request = NULL;
    CFReadStreamClose(requestReadStream);
    CFRelease(requestReadStream);
    requestReadStream = NULL;
    
    if (*error == nil) {
        return [self parseHostInfoFromHttpResponse:json];
    }
    return nil;
}

@end
