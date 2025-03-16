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
#import "HttpdnsInternalConstant.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsRequestManager_Internal.h"
#import "HttpdnsScheduleCenter.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsReachability.h"
#import "HttpdnsIPv6Adapter.h"
#import "HttpdnsInternalConstant.h"
#import "HttpdnsRequestManager.h"
#import "HttpdnsCFHttpWrapper.h"
#import "HttpdnsIpStackDetector.h"


static dispatch_queue_t _streamOperateSyncQueue = 0;

static NSURLSession *_resolveHostSession = nil;

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

#pragma mark init

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _streamOperateSyncQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.runloopOperateQueue.HttpdnsRequest", DISPATCH_QUEUE_SERIAL);
    });
}

- (instancetype)init {
    if (self = [super init]) {
        _sem = dispatch_semaphore_create(0);
        _resultData = [NSMutableData data];
        _httpJSONDict = nil;
        self.networkError = nil;
        _responseResolved = NO;
        _compeleted = NO;

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
            _resolveHostSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        });
    }
    return self;
}

#pragma mark LookupIpAction

- (HttpdnsHostObject *)parseHostInfoFromHttpResponse:(NSDictionary *)json withHostStr:(NSString *)host withQueryIpType:(HttpdnsQueryIPType)queryIpType {
    if (!json) {
        return nil;
    }

    NSArray *ip4s = [json objectForKey:@"ips"];
    if (!ip4s) {
        ip4s = @[];
    }

    NSArray *ip6s = [json objectForKey:@"ipsv6"];
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

    // 处理IPv6解析结果
    NSMutableArray *ip6Array = [NSMutableArray array];
    for (NSString *ipv6 in ip6s) {
        if ([HttpdnsUtil isEmptyString:ipv6]) {
            continue;
        }
        HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
        [ipObject setIp:ipv6];
        [ip6Array addObject:ipObject];
    }

    // SDNS场景额外返回一个extra字段
    if ([[json allKeys] containsObject:@"extra"]) {
        NSDictionary *extra = [self htmlEntityDecode:[json objectForKey:@"extra"]];
        [hostObject setExtra:extra];
    }
    [hostObject setHostName:host];
    [hostObject setV4Ips:ipArray];
    [hostObject setV6Ips:ip6Array];

    if ([[json allKeys] containsObject:@"client_ip"]) {
        NSString *clientIp = [json objectForKey:@"client_ip"];
        [hostObject setClientIp:clientIp];
    }

    int64_t returnedTTL = [[json objectForKey:@"ttl"] longLongValue];
    int64_t v4TTL = returnedTTL;
    int64_t v6TTL = returnedTTL;

    // 自定义ttl
    HttpDnsService *dnsService = [HttpDnsService sharedInstance];
    if (dnsService.ttlDelegate && [dnsService.ttlDelegate respondsToSelector:@selector(httpdnsHost:ipType:ttl:)]) {
        int64_t customTTL = [dnsService.ttlDelegate httpdnsHost:host ipType:AlicloudHttpDNS_IPTypeV64 ttl:returnedTTL];
        if (customTTL > 0) {
            v4TTL = customTTL;
            v6TTL = customTTL;
        } else {
            v4TTL = [dnsService.ttlDelegate httpdnsHost:host ipType:AlicloudHttpDNS_IPTypeV4 ttl:returnedTTL];
            v6TTL = [dnsService.ttlDelegate httpdnsHost:host ipType:AlicloudHttpDNS_IPTypeV6 ttl:returnedTTL];
        }
    }

    // 分别设置 v4ttl v6ttl
    if ([HttpdnsUtil isNotEmptyArray:ipArray]) {
        hostObject.v4ttl = v4TTL;
        hostObject.lastIPv4LookupTime = [HttpdnsUtil currentEpochTimeInSecond];
    }
    if ([HttpdnsUtil isNotEmptyArray:ip6Array]) {
        hostObject.v6ttl = v6TTL;
        hostObject.lastIPv6LookupTime = [HttpdnsUtil currentEpochTimeInSecond];
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

- (NSString *)appendQueryTypeToURL:(NSString *)originURL queryType:(HttpdnsQueryIPType)queryType {
    if (queryType & HttpdnsQueryIPTypeIpv4 && queryType & HttpdnsQueryIPTypeIpv6) {
        return [NSString stringWithFormat:@"%@&query=%@", originURL, [HttpdnsUtil URLEncodedString:@"4,6"]];
    } else if (queryType & HttpdnsQueryIPTypeIpv6) {
        return [NSString stringWithFormat:@"%@&query=%@", originURL, @"6"];
    } else {
        return originURL;
    }
}

- (NSString *)constructHttpdnsResolvingUrl:(HttpdnsRequest *)request forV4Net:(BOOL)isV4 {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];

    NSString *serverIp = isV4 ? [scheduleCenter currentActiveServiceServerV4Host] : [scheduleCenter currentActiveServiceServerV6Host];

    HttpDnsService *sharedService = [HttpDnsService sharedInstance];

    NSInteger accountId = sharedService.accountID;

    NSString *url = [NSString stringWithFormat:@"%@/%ld/d?host=%@", serverIp, accountId, request.host];

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

        url = [NSString stringWithFormat:@"%@/%ld/sign_d?host=%@&%@", serverIp, accountId, request.host, signatureRequestString];
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

    // 添加net
    NSString *netType = [[HttpdnsReachability sharedInstance] currentReachabilityString];
    if ([HttpdnsUtil isNotEmptyString:netType]) {
        url = [NSString stringWithFormat:@"%@&net=%@", url, netType];
    }

    // 添加查询类型
    url = [self appendQueryTypeToURL:url queryType:request.queryIpType];

    return url;
}

- (HttpdnsHostObject *)lookupHostFromServer:(HttpdnsRequest *)request error:(NSError **)error {
    HttpdnsLogDebug("lookupHostFromServer, request: %@", request);

    NSString *url = [self constructHttpdnsResolvingUrl:request forV4Net:YES];

    HttpdnsQueryIPType queryIPType = request.queryIpType;
    NSString *host = request.host;

    HttpdnsHostObject *hostObject = [self sendRequest:url host:host queryIpType:queryIPType error:error];

    if (!(*error)) {
        return hostObject;
    }

    @try {
        HttpdnsIPStackType stackType = [[HttpdnsIpStackDetector sharedInstance] currentIpStack];
        // 由于上面默认只用ipv4请求，这里判断如果是ipv6-only环境，那就用v6的ip再试一次
        if (stackType == kHttpdnsIpv6Only) {
            url = [self constructHttpdnsResolvingUrl:request forV4Net:NO];
            HttpdnsLogDebug("lookupHostFromServer by ipv4 server failed, construct ipv6 backup url: %@", url);
            return [self sendRequest:url host:host queryIpType:queryIPType error:error];
        }
    } @catch (NSException *exception) {
        HttpdnsLogDebug("lookupHostFromServer failed again by ipv6 server, exception: %@", exception.reason);
    }
    return hostObject;
}

- (HttpdnsHostObject *)sendRequest:(NSString *)urlStr host:(NSString *)host queryIpType:(HttpdnsQueryIPType)queryIPType error:(NSError **)error {
    HttpDnsService *httpdnsService = [HttpDnsService sharedInstance];
    if (httpdnsService.enableHttpsRequest || httpdnsService.hasAllowedArbitraryLoadsInATS) {
        NSString *fullUrlStr = httpdnsService.enableHttpsRequest
            ? [NSString stringWithFormat:@"https://%@", urlStr]
            : [NSString stringWithFormat:@"http://%@", urlStr];

        return [self sendURLSessionRequest:fullUrlStr host:host error:error queryIpType:queryIPType];
    } else {
        // 为了走HTTP时不强依赖用户的ATS配置，这里走使用CFHTTP实现的网络请求方式
        NSString *fullUrlStr = [NSString stringWithFormat:@"http://%@", urlStr];
        return [self sendCFHTTPRequest:fullUrlStr host:host error:error queryIpType:queryIPType];
    }
}

- (HttpdnsHostObject *)sendURLSessionRequest:(NSString *)urlStr host:(NSString *)host error:(NSError **)pError queryIpType:(HttpdnsQueryIPType)queryIpType {
    HttpdnsLogDebug("Send URLSession request URL: %@", urlStr);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:urlStr]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:[HttpDnsService sharedInstance].timeoutInterval];

    [request addValue:[HttpdnsUtil generateUserAgent] forHTTPHeaderField:@"User-Agent"];

    __block NSDictionary *json = nil;
    __block NSError *blockError = nil;
    __weak typeof(self) weakSelf = self;

    NSURLSessionTask *task = [_resolveHostSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            HttpdnsLogDebug("URLSession request network error, host: %@, error: %@", host, error);
            blockError = error;
        } else {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            HttpdnsLogDebug("Response code: %ld, body: %@", statusCode, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            if (statusCode == 200) {
                id jsonValue = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&blockError];
                if (!blockError) {
                    json = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
                }
            } else {
                NSString *errorMessage = [NSString stringWithFormat:@"Unsupported http status code: %ld", statusCode];
                blockError = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN code:ALICLOUD_HTTP_UNSUPPORTED_STATUS_CODE userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            }
        }
        dispatch_semaphore_signal(strongSelf->_sem);
    }];

    [task resume];
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);

    if (blockError && pError) {
        *pError = blockError;
        return nil;
    }

    if (!json && pError) {
        *pError = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN code:ALICLOUD_HTTP_PARSE_JSON_FAILED userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse JSON response"}];
        return nil;
    }

    return [self parseHostInfoFromHttpResponse:json withHostStr:host withQueryIpType:queryIpType];
}

- (HttpdnsHostObject *)sendCFHTTPRequest:(NSString *)urlStr host:(NSString *)host error:(NSError **)pError queryIpType:(HttpdnsQueryIPType)queryIpType {
    HttpdnsLogDebug("Send CFHTTP request URL: %@", urlStr);
    NSURL *url = [NSURL URLWithString:urlStr];

    __block NSDictionary *json = nil;
    __block NSError *blockError = nil;
    __weak typeof(self) weakSelf = self;

    [[HttpdnsCFHttpWrapper new] sendHTTPRequestWithURL:url completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            HttpdnsLogDebug("CFHTTP request network error, host: %@, error: %@", host, error);
            blockError = error;
        } else {
            id jsonValue = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&blockError];
            if (!blockError) {
                json = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
            }
        }

        dispatch_semaphore_signal(strongSelf->_sem);
    }];

    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);

    if (blockError && pError) {
        *pError = blockError;
        return nil;
    }

    if (!json && pError) {
        *pError = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN code:ALICLOUD_HTTP_PARSE_JSON_FAILED userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse JSON response"}];
        return nil;
    }

    return [self parseHostInfoFromHttpResponse:json withHostStr:host withQueryIpType:queryIpType];
}

- (HttpdnsRequestManager *)requestManager {
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    return sharedService.requestManager;
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

