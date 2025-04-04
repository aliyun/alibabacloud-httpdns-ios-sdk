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
#import "AlicloudHttpDNS.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsReachability.h"
#import "HttpdnsPublicConstant.h"
#import "HttpdnsInternalConstant.h"


static NSURLSession *_scheduleCenterSession = nil;

@interface HttpdnsScheduleExecutor()<NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@end

@implementation HttpdnsScheduleExecutor

- (instancetype)init {
    if (!(self = [super init])) {
        return nil;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        _scheduleCenterSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    });

    return self;
}

/**
 * 拼接 URL
 * 2024.6.12今天起，调度服务由后端就近调度，不再需要传入region参数，但为了兼容不传region默认就是国内region的逻辑，默认都传入region=global
 * https://203.107.1.1/100000/ss?region=global&platform=ios&sdk_version=3.1.7&sid=LpmJIA2CUoi4&net=wifi
 */
- (NSString *)constructRequestURLWithUpdateHost:(NSString *)updateHost {
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSString *urlPath = [NSString stringWithFormat:@"%ld/ss?region=global&platform=ios&sdk_version=%@", sharedService.accountID, HTTPDNS_IOS_SDK_VERSION];
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
                                                          timeoutInterval:[HttpDnsService sharedInstance].timeoutInterval];

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
