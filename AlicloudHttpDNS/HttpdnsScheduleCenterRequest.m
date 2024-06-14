//
//  HttpdnsScheduleCenterRequest.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/11.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsScheduleCenterRequest.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsConstants.h"
#import "HttpdnsConfig.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsUtil.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsgetNetworkInfoHelper.h"
#import "HttpdnsHostObject.h"

static NSURLSession *_scheduleCenterSession = nil;

@interface HttpdnsScheduleCenterRequest()<NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@end

@implementation HttpdnsScheduleCenterRequest

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

- (NSDictionary *)queryScheduleCenterRecordFromServerSync {
    return [self queryScheduleCenterRecordFromServerSyncWithHostIndex:0];
}

/// 获取调度IP List
- (NSArray *)getCenterHostList {
    NSArray *hostArray;
    if (ALICLOUD_HTTPDNS_JUDGE_SERVER_IP_CACHE == NO) { //服务IP缓存已读取
        if ([HttpdnsUtil isNotEmptyArray:ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST_IPV6]) {
            hostArray = ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST_IPV6;
        } else {
            hostArray = ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST;
        }
    } else { //服务IP缓存未读取
        if ([HttpdnsUtil isNotEmptyArray:ALICLOUD_HTTPDNS_SERVER_IPV6_LIST]) {
            hostArray = ALICLOUD_HTTPDNS_SERVER_IPV6_LIST;
        } else {
            hostArray = ALICLOUD_HTTPDNS_SERVER_IP_LIST;
        }
    }
    return hostArray;

}

- (NSDictionary *)queryScheduleCenterRecordFromServerSyncWithHostIndex:(NSInteger)hostIndex {
    NSArray *hostArray = [self getCenterHostList];

    NSInteger maxHostIndex = (hostArray.count - 1);
    if (hostIndex > maxHostIndex) {
        // 强降级策略 当服务IP轮询更新服务IP
        if (ALICLOUD_HTTPDNS_JUDGE_SERVER_IP_CACHE) {
            //强降级到启动IP
            ALICLOUD_HTTPDNS_JUDGE_SERVER_IP_CACHE = NO;
            return [self queryScheduleCenterRecordFromServerSyncWithHostIndex:0];
        }
        return nil;
    }

    NSError *error = nil;

    // 这里发起请求 返回数据
    NSDictionary *scheduleCenterRecord = [self queryScheduleCenterRecordFromServerWithHostIndex:hostIndex error:&error];

    if (error || !scheduleCenterRecord) {
        return [self queryScheduleCenterRecordFromServerSyncWithHostIndex:(hostIndex + 1)];
    }

    return scheduleCenterRecord;
}

- (NSString *)scheduleCenterHostFromIPIndex:(NSInteger)index {
    NSString *serverHostOrIP = nil;
    NSArray *hostArray = [self getCenterHostList];

    index = index % hostArray.count;
    serverHostOrIP = [HttpdnsUtil safeObjectAtIndexOrTheFirst:index array:hostArray defaultValue:nil];
    serverHostOrIP = [HttpdnsUtil getRequestHostFromString:serverHostOrIP];
    return serverHostOrIP;
}

/**
 * 拼接 URL
 * 2024.6.12今天起，调度服务由后端就近调度，不再需要传入region参数，但为了兼容不传region默认就是国内region的逻辑，默认都传入region=global
 * https://203.107.1.1/100000/ss?region=global&platform=ios&sdk_version=1.6.1&sid=LpmJIA2CUoi4&net=unknown&bssid=
 */
- (NSString *)constructRequestURLWithHostIndex:(NSInteger)hostIndex {
    NSString *serverIpOrHost = [self scheduleCenterHostFromIPIndex:hostIndex];
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSString *urlPath = [NSString stringWithFormat:@"%d/ss?region=global&platform=ios&sdk_version=%@", sharedService.accountID, HTTPDNS_IOS_SDK_VERSION];
    urlPath = [self urlFormatSidNetBssid:urlPath];
    urlPath = [urlPath stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"`#%^{}\"[]|\\<> "].invertedSet];
    NSString *url = [NSString stringWithFormat:@"https://%@/%@", serverIpOrHost, urlPath];
    return url;
}

// url 添加 sid net 和 bssid
- (NSString *)urlFormatSidNetBssid:(NSString *)url {
    NSString *sessionId = [HttpdnsUtil generateSessionID];
    if ([HttpdnsUtil isNotEmptyString:sessionId]) {
        url = [NSString stringWithFormat:@"%@&sid=%@", url, sessionId];
    }

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
    return url;
}

// 基于 URLSession 发送 HTTPS 请求
- (NSDictionary *)queryScheduleCenterRecordFromServerWithHostIndex:(NSInteger)hostIndex error:(NSError **)pError {
    NSString *fullUrlStr = [self constructRequestURLWithHostIndex:hostIndex];
    HttpdnsLogDebug("ScRequest URL: %@", fullUrlStr);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:fullUrlStr]
                                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                          timeoutInterval:[HttpDnsService sharedInstance].timeoutInterval];
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
                errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10002 userInfo:dict];
            } else {
                NSString *errCode = @"";
                errCode = [HttpdnsUtil safeObjectForKey:@"code" dict:result];
                NSDictionary *dict = nil;
                if ([HttpdnsUtil isNotEmptyString:errCode]) {
                    dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                            errCode, ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY, nil];
                }
                errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10003 userInfo:dict];
            }

            dispatch_semaphore_signal(_sem);
            return;
        }

        result = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
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
