//
//  HttpdnsScheduleExecutor.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/11.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsScheduleExecutor.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsInternalConstant.h"
#import "HttpdnsUtil.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsReachability.h"
#import "HttpdnsPublicConstant.h"
#import "HttpdnsInternalConstant.h"
#if __has_include(<Security/SecCertificate.h>)
#import <Security/SecCertificate.h>
#endif
#if __has_include(<Security/SecTrust.h>)
#import <Security/SecTrust.h>
#endif
#if __has_include(<Security/SecPolicy.h>)
#import <Security/SecPolicy.h>
#endif


static NSURLSession *_scheduleCenterSession = nil;

@interface HttpdnsScheduleExecutor()<NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@end

@implementation HttpdnsScheduleExecutor {
    NSInteger _accountId;
    NSTimeInterval _timeoutInterval;
}

- (instancetype)init {
    if (!(self = [super init])) {
        return nil;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        _scheduleCenterSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    });
    // 兼容旧路径：使用全局单例读取，但多账号场景下建议使用新init接口
    _accountId = [HttpDnsService sharedInstance].accountID;
    _timeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    return self;
}

- (instancetype)initWithAccountId:(NSInteger)accountId timeout:(NSTimeInterval)timeoutInterval {
    if (!(self = [self init])) {
        return nil;
    }
    _accountId = accountId;
    _timeoutInterval = timeoutInterval;
    return self;
}

/**
 * 拼接 URL
 * 2024.6.12今天起，调度服务由后端就近调度，不再需要传入region参数，但为了兼容不传region默认就是国内region的逻辑，默认都传入region=global
 * https://203.107.1.1/100000/ss?region=global&platform=ios&sdk_version=3.1.7&sid=LpmJIA2CUoi4&net=wifi
 */
- (NSString *)constructRequestURLWithUpdateHost:(NSString *)updateHost {
    NSString *urlPath = [NSString stringWithFormat:@"%ld/ss?region=global&platform=ios&sdk_version=%@", (long)_accountId, HTTPDNS_IOS_SDK_VERSION];
    urlPath = [self urlFormatSidNetBssid:urlPath];
    urlPath = [urlPath stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"`#%^{}\"[]|\\<> "].invertedSet];
    return [NSString stringWithFormat:@"https://%@/%@", updateHost, urlPath];
}

// url 添加 sid net
- (NSString *)urlFormatSidNetBssid:(NSString *)url {
    NSString *sessionId = [HttpdnsUtil generateSessionID];
    if ([HttpdnsUtil isNotEmptyString:sessionId]) {
        url = [NSString stringWithFormat:@"%@&sid=%@", url, sessionId];
    }

    NSString *netType = [[HttpdnsReachability sharedInstance] currentReachabilityString];
    if ([HttpdnsUtil isNotEmptyString:netType]) {
        url = [NSString stringWithFormat:@"%@&net=%@", url, netType];
    }
    return url;
}

- (NSDictionary *)fetchRegionConfigFromServer:(NSString *)updateHost error:(NSError **)pError {
    NSString *fullUrlStr = [self constructRequestURLWithUpdateHost:updateHost];
    HttpdnsLogDebug("ScRequest URL: %@", fullUrlStr);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:fullUrlStr]
                                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                          timeoutInterval:_timeoutInterval];

    [request addValue:[HttpdnsUtil generateUserAgent] forHTTPHeaderField:@"User-Agent"];

    __block NSDictionary * result = nil;
    __block NSError * errorStrong = nil;

    dispatch_semaphore_t _sem = dispatch_semaphore_create(0);

    NSURLSessionTask *stTask = [_scheduleCenterSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            HttpdnsLogDebug("ScRequest Network error: %@", error);
            errorStrong = error;
            dispatch_semaphore_signal(_sem);
            return;
        }

        NSInteger statusCode = [(NSHTTPURLResponse *) response statusCode];

        id jsonValue = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&errorStrong];

        if (statusCode != 200) {
            if (errorStrong) {
                NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                      @"Response code not 200, and parse response message error", @"ErrorMessage",
                                      [NSString stringWithFormat:@"%ld", (long)statusCode], @"ResponseCode", nil];
                errorStrong = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN code:ALICLOUD_HTTPDNS_HTTPS_NO_DATA_ERROR_CODE userInfo:dict];
            } else {
                NSString *errCode = @"Not200Response";
                errCode = [result objectForKey:@"code"];
                NSDictionary *dict = nil;
                if ([HttpdnsUtil isNotEmptyString:errCode]) {
                    dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                            errCode, ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY, nil];
                }
                errorStrong = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE userInfo:dict];
            }

            dispatch_semaphore_signal(_sem);
            return;
        }

        result = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
        HttpdnsLogDebug("ScRequest get response: %@", result);
        dispatch_semaphore_signal(_sem);
    }];

    [stTask resume];
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);

    if (!errorStrong) {
        return result;
    }

    if (pError != NULL) {
        *pError = errorStrong;
        HttpdnsLogDebug("ScRequest failed with scAddrURLString: %@, code: %ld, desc: %@", fullUrlStr, errorStrong.code, errorStrong.description);
    }
    return nil;
}


#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *_Nullable))completionHandler {
    if (!challenge) {
        return;
    }
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSString *validIP = ALICLOUD_HTTPDNS_VALID_SERVER_CERTIFICATE_IP;
        BOOL isServerTrustValid = NO;
        [self logServerCertificateSubject:challenge.protectionSpace.serverTrust];

        isServerTrustValid = [self evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:validIP];
        HttpdnsLogDebug("Evaluate serverTrust by %@ result: %d", validIP, isServerTrustValid);
        if (!isServerTrustValid) {
            NSURL *requestURL = task.currentRequest.URL ?: task.originalRequest.URL;
            NSString *targetDomain = requestURL.host;

            if ([HttpdnsUtil isNotEmptyString:targetDomain]) {
                isServerTrustValid = [self evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:targetDomain];
                HttpdnsLogDebug("Evaluate serverTrust by %@ result: %d", targetDomain, isServerTrustValid);
            }
        }
        if (isServerTrustValid) {
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

- (void)logServerCertificateSubject:(SecTrustRef)serverTrust {
    if (!serverTrust) {
        return;
    }
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    if (certificateCount <= 0) {
        HttpdnsLogDebug("Server trust has no certificate");
        return;
    }
    SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, 0);
    if (!certificate) {
        HttpdnsLogDebug("Failed to obtain server certificate");
        return;
    }
    CFStringRef subjectRef = SecCertificateCopySubjectSummary(certificate);
    if (subjectRef) {
        NSString *subject = (__bridge_transfer NSString *)subjectRef;
        HttpdnsLogDebug("HTTPS certificate subject: %@", subject);
    } else {
        HttpdnsLogDebug("Server certificate subject missing");
    }

#if defined(kSecOIDSubjectAltName)
    CFArrayRef targetKeys = (__bridge CFArrayRef) @[ (__bridge NSString *)kSecOIDSubjectAltName ];
    CFDictionaryRef rawAltNameValues = SecCertificateCopyValues(certificate, targetKeys, NULL);
    NSDictionary *altNameValues = CFBridgingRelease(rawAltNameValues);
    if (![altNameValues isKindOfClass:[NSDictionary class]]) {
        HttpdnsLogDebug("Server certificate SAN missing");
        return;
    }
    NSDictionary *altNameDict = altNameValues[(__bridge NSString *)kSecOIDSubjectAltName];
    if (![altNameDict isKindOfClass:[NSDictionary class]]) {
        HttpdnsLogDebug("Server certificate SAN entry missing");
        return;
    }
#else
    HttpdnsLogDebug("SAN key unsupported on current platform");
    return;
#endif
#if defined(kSecPropertyKeyValue)
    NSArray *sanItems = altNameDict[(__bridge NSString *)kSecPropertyKeyValue];
#else
    NSArray *sanItems = nil;
#endif
    if (![sanItems isKindOfClass:[NSArray class]] || sanItems.count == 0) {
        HttpdnsLogDebug("Server certificate SAN empty");
        return;
    }

    NSMutableArray<NSString *> *dnsNames = [NSMutableArray array];
    NSMutableArray<NSString *> *ipAddresses = [NSMutableArray array];
    for (NSDictionary *item in sanItems) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
#if defined(kSecPropertyKeyLabel)
        NSString *label = item[(__bridge NSString *)kSecPropertyKeyLabel];
#else
        NSString *label = nil;
#endif
#if defined(kSecPropertyKeyValue)
        id value = item[(__bridge NSString *)kSecPropertyKeyValue];
#else
        id value = nil;
#endif
        if (![label isKindOfClass:[NSString class]] || !value) {
            continue;
        }
        // 遍历SAN条目，按照标签区分域名与IP
        if ([label rangeOfString:@"DNS" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            if ([value isKindOfClass:[NSString class]]) {
                [dnsNames addObject:value];
            }
        } else if ([label rangeOfString:@"IP" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            if ([value isKindOfClass:[NSString class]]) {
                [ipAddresses addObject:value];
            }
        }
    }

    if (dnsNames.count > 0) {
        HttpdnsLogDebug("HTTPS certificate SAN DNS: %@", [dnsNames componentsJoinedByString:@","]);
    }
    if (ipAddresses.count > 0) {
        HttpdnsLogDebug("HTTPS certificate SAN IP: %@", [ipAddresses componentsJoinedByString:@","]);
    }
}

@end
