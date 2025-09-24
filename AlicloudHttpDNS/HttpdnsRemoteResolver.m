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
#import "HttpdnsRequest.h"
#import "HttpdnsRemoteResolver.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsInternalConstant.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsScheduleCenter.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsReachability.h"
#import "HttpdnsRequestManager.h"
#import "HttpdnsCFHttpWrapper.h"
#import "HttpdnsIpStackDetector.h"


static dispatch_queue_t _streamOperateSyncQueue = 0;

static NSURLSession *_resolveHostSession = nil;

@interface HttpdnsRemoteResolver () <NSStreamDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) NSRunLoop *runloop;
@property (nonatomic, strong) NSError *networkError;
@property (nonatomic, weak) HttpDnsService *service;

@end


@implementation HttpdnsRemoteResolver {
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

- (NSArray<HttpdnsHostObject *> *)parseHttpdnsResponse:(NSDictionary *)json withQueryIpType:(HttpdnsQueryIPType)queryIpType {
    if (!json) {
        return nil;
    }

    // 验证响应码
    if (![self validateResponseCode:json]) {
        return nil;
    }

    // 获取数据内容
    id data = [self extractDataContent:json];
    if (!data) {
        return nil;
    }

    // 获取所有答案
    NSArray *answers = [self getAnswersFromData:data];
    if (!answers) {
        return nil;
    }

    // 创建主机对象数组
    NSMutableArray<HttpdnsHostObject *> *hostObjects = [NSMutableArray array];
    for (NSDictionary *answer in answers) {
        HttpdnsHostObject *hostObject = [self createHostObjectFromAnswer:answer];
        if (hostObject) {
            [hostObjects addObject:hostObject];
        }
    }

    return hostObjects;
}

// 验证响应码
- (BOOL)validateResponseCode:(NSDictionary *)json {
    NSString *code = [json objectForKey:@"code"];
    if (![code isEqualToString:@"success"]) {
        HttpdnsLogDebug("Response code is not success: %@", code);
        return NO;
    }
    return YES;
}

// 获取并处理解密数据内容
- (id)extractDataContent:(NSDictionary *)json {
    // 获取mode，判断是否需要解密
    NSInteger mode = [[json objectForKey:@"mode"] integerValue];
    id data = [json objectForKey:@"data"];

    if (mode == 1) {  // 只处理AES-CBC模式
        // 需要解密
        data = [self decryptData:data withMode:mode];
    } else if (mode != 0) {
        // 不支持的加密模式（如AES-GCM）
        HttpdnsLogDebug("Unsupported encryption mode: %ld", (long)mode);
        return nil;
    }

    if (![data isKindOfClass:[NSDictionary class]]) {
        HttpdnsLogDebug("Data is not a dictionary");
        return nil;
    }

    return data;
}

// 解密数据
- (id)decryptData:(id)data withMode:(NSInteger)mode {
    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];
    NSString *aesSecretKey = service.aesSecretKey;

    if (![HttpdnsUtil isNotEmptyString:aesSecretKey]) {
        HttpdnsLogDebug("Response is encrypted but no AES key is provided");
        return nil;
    }

    if (![data isKindOfClass:[NSString class]]) {
        HttpdnsLogDebug("Encrypted data is not a string");
        return nil;
    }

    // 将Base64字符串转为NSData
    NSData *encryptedData = [[NSData alloc] initWithBase64EncodedString:data options:0];
    if (!encryptedData || encryptedData.length <= 16) {
        HttpdnsLogDebug("Invalid encrypted data");
        return nil;
    }

    // 从secretKey转换为二进制密钥
    NSData *keyData = [HttpdnsUtil dataFromHexString:aesSecretKey];
    if (!keyData) {
        HttpdnsLogDebug("Invalid AES key format");
        return nil;
    }

    // 使用工具类解密
    NSError *decryptError = nil;
    NSData *decryptedData = [HttpdnsUtil decryptDataAESCBC:encryptedData withKey:keyData error:&decryptError];

    if (decryptError || !decryptedData) {
        HttpdnsLogDebug("Failed to decrypt data: %@", decryptError);
        return nil;
    }

    // 将解密后的JSON数据解析为字典
    NSError *jsonError;
    id decodedData = [NSJSONSerialization JSONObjectWithData:decryptedData options:0 error:&jsonError];

    if (jsonError) {
        HttpdnsLogDebug("Failed to parse decrypted JSON: %@", jsonError);
        return nil;
    }

    return decodedData;
}

// 从数据中获取答案数组
- (NSArray *)getAnswersFromData:(NSDictionary *)data {
    NSArray *answers = [data objectForKey:@"answers"];
    if (![answers isKindOfClass:[NSArray class]] || answers.count == 0) {
        HttpdnsLogDebug("No answers in response");
        return nil;
    }
    return answers;
}

// 从答案创建主机对象
- (HttpdnsHostObject *)createHostObjectFromAnswer:(NSDictionary *)answer {
    // 获取域名
    NSString *host = [answer objectForKey:@"dn"];
    if (![HttpdnsUtil isNotEmptyString:host]) {
        HttpdnsLogDebug("Missing domain name in answer");
        return nil;
    }

    // 创建并填充HostObject
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    [hostObject setHostName:host];

    // 处理IPv4信息
    [self processIPv4Info:answer forHostObject:hostObject];

    // 处理IPv6信息
    [self processIPv6Info:answer forHostObject:hostObject];

    // 自定义ttl
    [HttpdnsUtil processCustomTTL:hostObject forHost:host service:self.service];

    // 设置客户端IP
    NSString *clientIp = [[answer objectForKey:@"data"] objectForKey:@"cip"];
    if ([HttpdnsUtil isNotEmptyString:clientIp]) {
        [hostObject setClientIp:clientIp];
    }

    return hostObject;
}

// 处理IPv4信息
- (void)processIPv4Info:(NSDictionary *)answer forHostObject:(HttpdnsHostObject *)hostObject {
    NSDictionary *v4Data = [answer objectForKey:@"v4"];
    if (![v4Data isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSArray *ip4s = [v4Data objectForKey:@"ips"];
    if ([ip4s isKindOfClass:[NSArray class]] && ip4s.count > 0) {
        // 处理IPv4地址
        [self setIpArrayToHostObject:hostObject fromIpsArray:ip4s forIPv6:NO];

        // 设置IPv4的TTL
        [self setTTLForHostObject:hostObject fromData:v4Data forIPv6:NO];

        // 处理v4的extra字段，优先使用
        [self processExtraInfo:v4Data forHostObject:hostObject];

        // 检查是否有no_ip_code字段，表示无IPv4记录
        if ([[v4Data objectForKey:@"no_ip_code"] isKindOfClass:[NSString class]]) {
            hostObject.hasNoIpv4Record = YES;
        }
    } else {
        // 没有IPv4地址但有v4节点，可能是无记录
        hostObject.hasNoIpv4Record = YES;
    }
}

// 处理IPv6信息
- (void)processIPv6Info:(NSDictionary *)answer forHostObject:(HttpdnsHostObject *)hostObject {
    NSDictionary *v6Data = [answer objectForKey:@"v6"];
    if (![v6Data isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSArray *ip6s = [v6Data objectForKey:@"ips"];
    if ([ip6s isKindOfClass:[NSArray class]] && ip6s.count > 0) {
        // 处理IPv6地址
        [self setIpArrayToHostObject:hostObject fromIpsArray:ip6s forIPv6:YES];

        // 设置IPv6的TTL
        [self setTTLForHostObject:hostObject fromData:v6Data forIPv6:YES];

        // 只有在没有v4 extra的情况下才使用v6的extra
        if (![hostObject getExtra]) {
            [self processExtraInfo:v6Data forHostObject:hostObject];
        }

        // 检查是否有no_ip_code字段，表示无IPv6记录
        if ([[v6Data objectForKey:@"no_ip_code"] isKindOfClass:[NSString class]]) {
            hostObject.hasNoIpv6Record = YES;
        }
    } else {
        // 没有IPv6地址但有v6节点，可能是无记录
        hostObject.hasNoIpv6Record = YES;
    }
}

// 设置IP数组到主机对象
- (void)setIpArrayToHostObject:(HttpdnsHostObject *)hostObject fromIpsArray:(NSArray *)ips forIPv6:(BOOL)isIPv6 {
    NSMutableArray *ipArray = [NSMutableArray array];
    for (NSString *ip in ips) {
        if ([HttpdnsUtil isEmptyString:ip]) {
            continue;
        }
        HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
        [ipObject setIp:ip];
        [ipArray addObject:ipObject];
    }

    if (isIPv6) {
        [hostObject setV6Ips:ipArray];
    } else {
        [hostObject setV4Ips:ipArray];
    }
}

// 设置TTL
- (void)setTTLForHostObject:(HttpdnsHostObject *)hostObject fromData:(NSDictionary *)data forIPv6:(BOOL)isIPv6 {
    NSNumber *ttl = [data objectForKey:@"ttl"];
    if (ttl) {
        if (isIPv6) {
            hostObject.v6ttl = [ttl longLongValue];
            hostObject.lastIPv6LookupTime = [NSDate date].timeIntervalSince1970;
        } else {
            hostObject.v4ttl = [ttl longLongValue];
            hostObject.lastIPv4LookupTime = [NSDate date].timeIntervalSince1970;
        }
    } else {
        if (isIPv6) {
            hostObject.v6ttl = 0;
        } else {
            hostObject.v4ttl = 0;
        }
    }
}

// 处理额外信息
- (void)processExtraInfo:(NSDictionary *)data forHostObject:(HttpdnsHostObject *)hostObject {
    id extra = [data objectForKey:@"extra"];
    if (extra) {
        NSString *convertedExtra = [self convertExtraToString:extra];
        if (convertedExtra) {
            [hostObject setExtra:convertedExtra];
        }
    }
}

- (NSString *)constructHttpdnsResolvingUrl:(HttpdnsRequest *)request forV4Net:(BOOL)isV4 {
    // 获取基础信息
    NSString *serverIp = [self getServerIpForNetwork:isV4];
    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];

    // 准备签名和加密参数
    NSDictionary *paramsToSign = [self prepareSigningParams:request forEncryption:[self shouldUseEncryption]];

    // 计算签名
    NSString *signature = [self calculateSignatureForParams:paramsToSign withSecretKey:service.secretKey];

    // 构建URL
    NSString *url = [NSString stringWithFormat:@"%@/v2/d", serverIp];

    // 添加所有参数并构建最终URL
    NSString *finalUrl = [self buildFinalUrlWithBase:url
                                              params:paramsToSign
                                         isEncrypted:[self shouldUseEncryption]
                                           signature:signature
                                             request:request];

    HttpdnsLogDebug("Constructed v2 API URL: %@", finalUrl);
    return finalUrl;
}

// 获取当前应使用的服务器IP
- (NSString *)getServerIpForNetwork:(BOOL)isV4 {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    return isV4 ? [scheduleCenter currentActiveServiceServerV4Host] :
                  [scheduleCenter currentActiveServiceServerV6Host];
}

// 检查是否应该使用加密
- (BOOL)shouldUseEncryption {
    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];
    return [HttpdnsUtil isNotEmptyString:service.aesSecretKey];
}

// 准备需要进行签名的参数
- (NSDictionary *)prepareSigningParams:(HttpdnsRequest *)request forEncryption:(BOOL)useEncryption {
    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];
    NSInteger accountId = service.accountID;

    // 构建参与签名的参数字典
    NSMutableDictionary *paramsToSign = [NSMutableDictionary dictionary];

    // 构建需要加密的参数字典
    NSMutableDictionary *paramsToEncrypt = [NSMutableDictionary dictionary];

    // 账号ID，参与签名但不加密
    [paramsToSign setObject:[NSString stringWithFormat:@"%ld", accountId] forKey:@"id"];

    // 决定加密模式
    NSString *mode = useEncryption ? @"1" : @"0"; // 0: 明文模式, 1: AES-CBC加密模式
    [paramsToSign setObject:mode forKey:@"m"];

    // 版本号，参与签名但不加密
    [paramsToSign setObject:@"1.0" forKey:@"v"];

    // 域名参数，参与签名并加密
    [paramsToEncrypt setObject:request.host forKey:@"dn"];

    // 查询类型，参与签名并加密
    [paramsToEncrypt setObject:[self getQueryTypeString:request.queryIpType] forKey:@"q"];

    // SDNS参数，参与签名并加密
    [self addSdnsParams:request.sdnsParams toParams:paramsToEncrypt];

    // 签名过期时间，参与签名但不加密
    long expiredTimestamp = [self calculateExpiredTimestamp];
    NSString *expiredTimestampString = [NSString stringWithFormat:@"%ld", expiredTimestamp];
    [paramsToSign setObject:expiredTimestampString forKey:@"exp"];

    // 处理加密
    if (useEncryption) {
        NSString *encryptedHexString = [self encryptParams:paramsToEncrypt];
        if (encryptedHexString) {
            [paramsToSign setObject:encryptedHexString forKey:@"enc"];
        }
    } else {
        // 明文模式下，加密参数也放入签名参数中
        [paramsToSign addEntriesFromDictionary:paramsToEncrypt];
    }

    return paramsToSign;
}

// 获取查询类型字符串
- (NSString *)getQueryTypeString:(HttpdnsQueryIPType)queryIpType {
    if ((queryIpType & HttpdnsQueryIPTypeIpv4) && (queryIpType & HttpdnsQueryIPTypeIpv6)) {
        return @"4,6";
    } else if (queryIpType & HttpdnsQueryIPTypeIpv6) {
        return @"6";
    }
    return @"4";
}

// 添加SDNS参数
- (void)addSdnsParams:(NSDictionary *)sdnsParams toParams:(NSMutableDictionary *)paramsToEncrypt {
    if ([HttpdnsUtil isNotEmptyDictionary:sdnsParams]) {
        [sdnsParams enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            NSString *sdnsKey = [NSString stringWithFormat:@"sdns-%@", key];
            [paramsToEncrypt setObject:obj forKey:sdnsKey];
        }];
    }
}

// 计算过期时间戳
- (long)calculateExpiredTimestamp {
    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];
    long localTimestampOffset = (long)service.authTimeOffset;
    long localTimestamp = (long)[[NSDate date] timeIntervalSince1970];
    if (localTimestampOffset != 0) {
        localTimestamp = localTimestamp + localTimestampOffset;
    }
    return localTimestamp + HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL;
}

// 加密参数
- (NSString *)encryptParams:(NSDictionary *)paramsToEncrypt {
    NSError *error = nil;
    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];

    // 将待加密参数转为JSON
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:paramsToEncrypt options:0 error:&error];
    if (error) {
        HttpdnsLogDebug("Failed to serialize params to JSON: %@", error);
        return nil;
    }

    // 从secretKey转换为二进制密钥
    NSData *keyData = [HttpdnsUtil dataFromHexString:service.aesSecretKey];
    if (!keyData) {
        HttpdnsLogDebug("Invalid AES key format");
        return nil;
    }

    // 目前在OC中没有比较好的实现AES-GCM的方式，因此这里选择AES-CBC加密
    NSData *encryptedData = [HttpdnsUtil encryptDataAESCBC:jsonData withKey:keyData error:&error];
    if (error) {
        HttpdnsLogDebug("Failed to encrypt data: %@", error);
        return nil;
    }

    // 将加密结果转为十六进制字符串
    return [HttpdnsUtil hexStringFromData:encryptedData];
}

// 计算签名
- (NSString *)calculateSignatureForParams:(NSDictionary *)params withSecretKey:(NSString *)secretKey {
    if (![HttpdnsUtil isNotEmptyString:secretKey]) {
        return nil;
    }

    // 按照签名要求对参数进行排序并生成签名内容
    NSArray *sortedKeys = [[params allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *signParts = [NSMutableArray array];

    for (NSString *key in sortedKeys) {
        [signParts addObject:[NSString stringWithFormat:@"%@=%@", key, [params objectForKey:key]]];
    }

    // 组合签名字符串
    NSString *signContent = [signParts componentsJoinedByString:@"&"];

    // 计算HMAC-SHA256签名
    return [HttpdnsUtil hmacSha256:signContent key:secretKey];
}

// 构建最终URL
- (NSString *)buildFinalUrlWithBase:(NSString *)baseUrl
                             params:(NSDictionary *)params
                        isEncrypted:(BOOL)useEncryption
                          signature:(NSString *)signature
                            request:(HttpdnsRequest *)request {

    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];
    NSMutableString *finalUrl = [NSMutableString stringWithString:baseUrl];
    [finalUrl appendString:@"?"];

    // 首先添加必要参数
    [finalUrl appendFormat:@"id=%ld", service.accountID];
    [finalUrl appendFormat:@"&m=%@", [params objectForKey:@"m"]];
    [finalUrl appendFormat:@"&exp=%@", [params objectForKey:@"exp"]];
    [finalUrl appendFormat:@"&v=%@", [params objectForKey:@"v"]];

    if (useEncryption) {
        // 加密模式下，添加enc参数
        [finalUrl appendFormat:@"&enc=%@", [params objectForKey:@"enc"]];
    } else {
        // 明文模式下，添加所有参数
        NSMutableDictionary *paramsForPlainText = [NSMutableDictionary dictionaryWithDictionary:params];
        [paramsForPlainText removeObjectForKey:@"id"];
        [paramsForPlainText removeObjectForKey:@"m"];
        [paramsForPlainText removeObjectForKey:@"exp"];
        [paramsForPlainText removeObjectForKey:@"v"];

        for (NSString *key in paramsForPlainText) {
            // 跳过已添加的参数
            if ([key isEqualToString:@"id"] || [key isEqualToString:@"m"] ||
                [key isEqualToString:@"exp"] || [key isEqualToString:@"v"]) {
                continue;
            }

            NSString *value = [paramsForPlainText objectForKey:key];
            [finalUrl appendFormat:@"&%@=%@", [HttpdnsUtil URLEncodedString:key], [HttpdnsUtil URLEncodedString:value]];
        }
    }

    // 添加签名（如果有）
    if ([HttpdnsUtil isNotEmptyString:signature]) {
        [finalUrl appendFormat:@"&s=%@", signature];
    }

    // 添加不参与签名的其他参数
    [self appendAdditionalParams:finalUrl];

    return finalUrl;
}

// 添加额外的不参与签名的参数
- (void)appendAdditionalParams:(NSMutableString *)url {
    // sessionId
    NSString *sessionId = [HttpdnsUtil generateSessionID];
    if ([HttpdnsUtil isNotEmptyString:sessionId]) {
        [url appendFormat:@"&sid=%@", sessionId];
    }

    // 网络类型
    NSString *netType = [[HttpdnsReachability sharedInstance] currentReachabilityString];
    if ([HttpdnsUtil isNotEmptyString:netType]) {
        [url appendFormat:@"&net=%@", netType];
    }

    // SDK版本
    NSString *versionInfo = [NSString stringWithFormat:@"ios_%@", HTTPDNS_IOS_SDK_VERSION];
    [url appendFormat:@"&sdk=%@", versionInfo];
}

- (NSArray<HttpdnsHostObject *> *)resolve:(HttpdnsRequest *)request error:(NSError **)error {
    HttpdnsLogDebug("lookupHostFromServer, request: %@", request);

    HttpDnsService *service = [HttpDnsService getInstanceByAccountId:request.accountId];
    if (!service) {
        service = [HttpDnsService sharedInstance];
    }
    self.service = service;

    NSString *url = [self constructHttpdnsResolvingUrl:request forV4Net:YES];

    HttpdnsQueryIPType queryIPType = request.queryIpType;

    NSArray<HttpdnsHostObject *> *hostObjects = [self sendRequest:url queryIpType:queryIPType error:error];

    if (!(*error)) {
        return hostObjects;
    }

    @try {
        HttpdnsIPStackType stackType = [[HttpdnsIpStackDetector sharedInstance] currentIpStack];
        // 由于上面默认只用ipv4请求，这里判断如果是ipv6-only环境，那就用v6的ip再试一次
        if (stackType == kHttpdnsIpv6Only) {
            url = [self constructHttpdnsResolvingUrl:request forV4Net:NO];
            HttpdnsLogDebug("lookupHostFromServer by ipv4 server failed, construct ipv6 backup url: %@", url);
            hostObjects = [self sendRequest:url queryIpType:queryIPType error:error];

            if (!(*error)) {
                return hostObjects;
            }
        }
    } @catch (NSException *exception) {
        HttpdnsLogDebug("lookupHostFromServer failed again by ipv6 server, exception: %@", exception.reason);
    }
    return nil;
}

- (NSArray<HttpdnsHostObject *> *)sendRequest:(NSString *)urlStr queryIpType:(HttpdnsQueryIPType)queryIPType error:(NSError **)error {
    HttpDnsService *httpdnsService = self.service ?: [HttpDnsService sharedInstance];
    if (httpdnsService.enableHttpsRequest || httpdnsService.hasAllowedArbitraryLoadsInATS) {
        NSString *fullUrlStr = httpdnsService.enableHttpsRequest
            ? [NSString stringWithFormat:@"https://%@", urlStr]
            : [NSString stringWithFormat:@"http://%@", urlStr];

        return [self sendURLSessionRequest:fullUrlStr error:error queryIpType:queryIPType];
    } else {
        // 为了走HTTP时不强依赖用户的ATS配置，这里走使用CFHTTP实现的网络请求方式
        NSString *fullUrlStr = [NSString stringWithFormat:@"http://%@", urlStr];
        return [self sendCFHTTPRequest:fullUrlStr error:error queryIpType:queryIPType];
    }
}

- (NSArray<HttpdnsHostObject *> *)sendURLSessionRequest:(NSString *)urlStr error:(NSError **)pError queryIpType:(HttpdnsQueryIPType)queryIpType {
    HttpdnsLogDebug("Send URLSession request URL: %@", urlStr);
    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:urlStr]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:service.timeoutInterval];

    [request addValue:[HttpdnsUtil generateUserAgent] forHTTPHeaderField:@"User-Agent"];

    __block NSDictionary *json = nil;
    __block NSError *blockError = nil;
    __weak typeof(self) weakSelf = self;

    NSURLSessionTask *task = [_resolveHostSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            HttpdnsLogDebug("URLSession request network error, url: %@, error: %@", urlStr, error);
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

    return [self parseHttpdnsResponse:json withQueryIpType:queryIpType];
}

- (NSArray<HttpdnsHostObject *> *)sendCFHTTPRequest:(NSString *)urlStr error:(NSError **)pError queryIpType:(HttpdnsQueryIPType)queryIpType {
    HttpdnsLogDebug("Send CFHTTP request URL: %@", urlStr);
    NSURL *url = [NSURL URLWithString:urlStr];
    HttpDnsService *service = self.service ?: [HttpDnsService sharedInstance];

    __block NSDictionary *json = nil;
    __block NSError *blockError = nil;
    __weak typeof(self) weakSelf = self;

    [[HttpdnsCFHttpWrapper new] sendHTTPRequestWithURL:url
                                      timeoutInterval:service.timeoutInterval
                                           completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            HttpdnsLogDebug("CFHTTP request network error, urlStr: %@, error: %@", urlStr, error);
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

    return [self parseHttpdnsResponse:json withQueryIpType:queryIpType];
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


#pragma mark - Helper Functions
// 将extra字段转换为NSString类型
- (NSString *)convertExtraToString:(id)extra {
    if (!extra) {
        return nil;
    }

    if ([extra isKindOfClass:[NSString class]]) {
        // 已经是字符串，直接返回
        return extra;
    } else {
        // 非字符串，尝试转换为JSON字符串
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:extra options:0 error:&error];
        if (!error && jsonData) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            return jsonString;
        } else {
            HttpdnsLogDebug("Failed to convert extra to JSON string: %@", error);
            return nil;
        }
    }
}

@end
