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

- (HttpdnsHostObject *)parseHostInfoFromHttpResponse:(NSDictionary *)json withHostStr:(NSString *)host withQueryIpType:(HttpdnsQueryIPType)queryIpType {
    if (!json) {
        return nil;
    }

    // 解密处理
    NSString *code = [json objectForKey:@"code"];
    if (![code isEqualToString:@"success"]) {
        HttpdnsLogDebug("Response code is not success: %@", code);
        return nil;
    }

    // 获取mode，判断是否需要解密
    NSInteger mode = [[json objectForKey:@"mode"] integerValue];
    id data = [json objectForKey:@"data"];

    if (mode == 1) {  // 只处理AES-CBC模式
        // 需要解密
        HttpDnsService *sharedService = [HttpDnsService sharedInstance];
        NSString *aesSecretKey = sharedService.aesSecretKey;

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
        data = [NSJSONSerialization JSONObjectWithData:decryptedData options:0 error:&jsonError];

        if (jsonError) {
            HttpdnsLogDebug("Failed to parse decrypted JSON: %@", jsonError);
            return nil;
        }
    } else if (mode != 0) {
        // 不支持的加密模式（如AES-GCM）
        HttpdnsLogDebug("Unsupported encryption mode: %ld", (long)mode);
        return nil;
    }

    if (![data isKindOfClass:[NSDictionary class]]) {
        HttpdnsLogDebug("Data is not a dictionary");
        return nil;
    }

    // 从data中获取answers数组
    NSArray *answers = [data objectForKey:@"answers"];
    if (![answers isKindOfClass:[NSArray class]] || answers.count == 0) {
        HttpdnsLogDebug("No answers in response");
        return nil;
    }

    // 查找与请求的host匹配的答案
    NSDictionary *targetAnswer = nil;
    for (NSDictionary *answer in answers) {
        NSString *dn = [answer objectForKey:@"dn"];
        if ([dn isEqualToString:host]) {
            targetAnswer = answer;
            break;
        }
    }

    if (!targetAnswer) {
        HttpdnsLogDebug("No answer found for host: %@", host);
        return nil;
    }

    // 创建并填充HostObject
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    [hostObject setHostName:host];

    // 获取IPv4信息
    NSDictionary *v4Data = [targetAnswer objectForKey:@"v4"];
    if ([v4Data isKindOfClass:[NSDictionary class]]) {
        NSArray *ip4s = [v4Data objectForKey:@"ips"];
        if ([ip4s isKindOfClass:[NSArray class]] && ip4s.count > 0) {
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
            [hostObject setV4Ips:ipArray];

            // 设置IPv4的TTL
            NSNumber *ttl = [v4Data objectForKey:@"ttl"];
            if (ttl) {
                hostObject.v4ttl = [ttl longLongValue];
                hostObject.lastIPv4LookupTime = [NSDate date].timeIntervalSince1970;
            } else {
                hostObject.v4ttl = 0;
            }

            // 处理v4的extra字段，优先使用
            id v4Extra = [v4Data objectForKey:@"extra"];
            if (v4Extra) {
                NSString *convertedExtra = [self convertExtraToString:v4Extra];
                if (convertedExtra) {
                    [hostObject setExtra:convertedExtra];
                }
            }

            // 检查是否有no_ip_code字段，表示无IPv4记录
            if ([[v4Data objectForKey:@"no_ip_code"] isKindOfClass:[NSString class]]) {
                hostObject.hasNoIpv4Record = YES;
            }
        } else {
            // 没有IPv4地址但有v4节点，可能是无记录
            hostObject.hasNoIpv4Record = YES;
        }
    }

    // 获取IPv6信息
    NSDictionary *v6Data = [targetAnswer objectForKey:@"v6"];
    if ([v6Data isKindOfClass:[NSDictionary class]]) {
        NSArray *ip6s = [v6Data objectForKey:@"ips"];
        if ([ip6s isKindOfClass:[NSArray class]] && ip6s.count > 0) {
            // 处理ipv6
            NSMutableArray *ip6Array = [NSMutableArray array];
            for (NSString *ipv6 in ip6s) {
                if ([HttpdnsUtil isEmptyString:ipv6]) {
                    continue;
                }
                HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
                [ipObject setIp:ipv6];
                [ip6Array addObject:ipObject];
            }
            [hostObject setV6Ips:ip6Array];

            // 设置IPv6的TTL
            NSNumber *ttl = [v6Data objectForKey:@"ttl"];
            if (ttl) {
                hostObject.v6ttl = [ttl longLongValue];
                hostObject.lastIPv6LookupTime = [NSDate date].timeIntervalSince1970;
            } else {
                hostObject.v6ttl = 0;
            }

            // 只有在没有v4 extra的情况下才使用v6的extra
            if (![hostObject getExtra]) {
                id v6Extra = [v6Data objectForKey:@"extra"];
                if (v6Extra) {
                    NSString *convertedExtra = [self convertExtraToString:v6Extra];
                    if (convertedExtra) {
                        [hostObject setExtra:convertedExtra];
                    }
                }
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

    // 自定义ttl
    HttpDnsService *dnsService = [HttpDnsService sharedInstance];
    if (dnsService.ttlDelegate && [dnsService.ttlDelegate respondsToSelector:@selector(httpdnsHost:ipType:ttl:)]) {
        if ([HttpdnsUtil isNotEmptyArray:[hostObject getV4Ips]]) {
            int64_t customV4TTL = [dnsService.ttlDelegate httpdnsHost:host ipType:AlicloudHttpDNS_IPTypeV4 ttl:hostObject.v4ttl];
            if (customV4TTL > 0) {
                hostObject.v4ttl = customV4TTL;
            }
        }

        if ([HttpdnsUtil isNotEmptyArray:[hostObject getV6Ips]]) {
            int64_t customV6TTL = [dnsService.ttlDelegate httpdnsHost:host ipType:AlicloudHttpDNS_IPTypeV6 ttl:hostObject.v6ttl];
            if (customV6TTL > 0) {
                hostObject.v6ttl = customV6TTL;
            }
        }
    }

    // 设置客户端IP
    NSString *clientIp = [data objectForKey:@"cip"];
    if ([HttpdnsUtil isNotEmptyString:clientIp]) {
        [hostObject setClientIp:clientIp];
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
    NSString *secretKey = sharedService.secretKey;

    // 构建参与签名的参数字典
    NSMutableDictionary *paramsToSign = [NSMutableDictionary dictionary];

    // 构建需要加密的参数字典
    NSMutableDictionary *paramsToEncrypt = [NSMutableDictionary dictionary];

    // 账号ID，参与签名但不加密
    [paramsToSign setObject:[NSString stringWithFormat:@"%ld", accountId] forKey:@"id"];

    // 决定加密模式
    BOOL useEncryption = [HttpdnsUtil isNotEmptyString:sharedService.aesSecretKey];
    NSString *mode = useEncryption ? @"1" : @"0"; // 0: 明文模式, 1: AES-CBC加密模式
    [paramsToSign setObject:mode forKey:@"m"];

    // 版本号，参与签名但不加密
    [paramsToSign setObject:@"1.0" forKey:@"v"];

    // 域名参数，参与签名并加密
    [paramsToEncrypt setObject:request.host forKey:@"dn"];

    // 查询类型，参与签名并加密
    NSString *queryTypeStr = @"4";
    if (request.queryIpType & HttpdnsQueryIPTypeBoth) {
        queryTypeStr = @"4,6";
    } else if (request.queryIpType & HttpdnsQueryIPTypeIpv6) {
        queryTypeStr = @"6";
    }
    [paramsToEncrypt setObject:queryTypeStr forKey:@"q"];

    // SDNS参数，参与签名并加密
    if ([HttpdnsUtil isNotEmptyDictionary:request.sdnsParams]) {
        [request.sdnsParams enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            NSString *sdnsKey = [NSString stringWithFormat:@"sdns-%@", key];
            [paramsToEncrypt setObject:obj forKey:sdnsKey];
        }];
    }

    // 签名过期时间，参与签名但不加密
    long localTimestampOffset = (long)sharedService.authTimeOffset;
    long localTimestamp = (long)[[NSDate date] timeIntervalSince1970];
    if (localTimestampOffset != 0) {
        localTimestamp = localTimestamp + localTimestampOffset;
    }
    long expiredTimestamp = localTimestamp + HTTPDNS_DEFAULT_AUTH_TIMEOUT_INTERVAL;
    NSString *expiredTimestampString = [NSString stringWithFormat:@"%ld", expiredTimestamp];
    [paramsToSign setObject:expiredTimestampString forKey:@"exp"];

    // 处理加密
    if (useEncryption) {
        NSError *error = nil;

        // 将待加密参数转为JSON
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:paramsToEncrypt options:0 error:&error];
        if (error) {
            HttpdnsLogDebug("Failed to serialize params to JSON: %@", error);
            return nil;
        }

        // 从secretKey转换为二进制密钥
        NSData *keyData = [HttpdnsUtil dataFromHexString:sharedService.aesSecretKey];
        if (!keyData) {
            HttpdnsLogDebug("Invalid AES key format");
            return nil;
        }

        // AES-CBC加密
        NSData *encryptedData = [HttpdnsUtil encryptDataAESCBC:jsonData withKey:keyData error:&error];
        if (error) {
            HttpdnsLogDebug("Failed to encrypt data: %@", error);
            return nil;
        }

        // 将加密结果转为十六进制字符串
        NSString *encryptedHexString = [HttpdnsUtil hexStringFromData:encryptedData];
        [paramsToSign setObject:encryptedHexString forKey:@"enc"];
    } else {
        // 明文模式下，加密参数也放入签名参数中
        [paramsToSign addEntriesFromDictionary:paramsToEncrypt];
    }

    // 按照签名要求对参数进行排序并生成签名内容
    NSArray *sortedKeys = [[paramsToSign allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *signParts = [NSMutableArray array];

    for (NSString *key in sortedKeys) {
        [signParts addObject:[NSString stringWithFormat:@"%@=%@", key, [paramsToSign objectForKey:key]]];
    }

    // 组合签名字符串
    NSString *signContent = [signParts componentsJoinedByString:@"&"];

    // 计算HMAC-SHA256签名
    NSString *signature = nil;
    if ([HttpdnsUtil isNotEmptyString:secretKey]) {
        signature = [HttpdnsUtil hmacSha256:signContent key:secretKey];
    }

    // 构建基础URL
    NSString *url = [NSString stringWithFormat:@"%@/v2/d", serverIp];

    // 构建最终URL
    NSMutableString *finalUrl = [NSMutableString stringWithString:url];
    [finalUrl appendString:@"?"];

    // 首先添加必要参数
    [finalUrl appendFormat:@"id=%ld", accountId];
    [finalUrl appendFormat:@"&m=%@", mode];
    [finalUrl appendFormat:@"&exp=%@", expiredTimestampString];
    [finalUrl appendFormat:@"&v=%@", @"1.0"];

    if (useEncryption) {
        // 加密模式下，添加enc参数
        [finalUrl appendFormat:@"&enc=%@", [paramsToSign objectForKey:@"enc"]];
    } else {
        // 明文模式下，添加所有加密参数
        for (NSString *key in paramsToEncrypt) {
            NSString *value = [paramsToEncrypt objectForKey:key];
            [finalUrl appendFormat:@"&%@=%@", [HttpdnsUtil URLEncodedString:key], [HttpdnsUtil URLEncodedString:value]];
        }
    }

    // 添加签名（如果有）
    if ([HttpdnsUtil isNotEmptyString:signature]) {
        [finalUrl appendFormat:@"&s=%@", signature];
    }

    // 添加不参与签名的其他历史参数
    // sessionId
    NSString *sessionId = [HttpdnsUtil generateSessionID];
    if ([HttpdnsUtil isNotEmptyString:sessionId]) {
        [finalUrl appendFormat:@"&sid=%@", sessionId];
    }

    // 网络类型
    NSString *netType = [[HttpdnsReachability sharedInstance] currentReachabilityString];
    if ([HttpdnsUtil isNotEmptyString:netType]) {
        [finalUrl appendFormat:@"&net=%@", netType];
    }

    // SDK版本
    NSString *versionInfo = [NSString stringWithFormat:@"ios_%@", HTTPDNS_IOS_SDK_VERSION];
    [finalUrl appendFormat:@"&sdk=%@", versionInfo];

    HttpdnsLogDebug("Constructed v2 API URL: %@", finalUrl);
    return finalUrl;
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

