//
//  HttpdnsScheduleCenterRequest.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/11.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsScheduleCenterRequest.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsConstants.h"
#import "HttpdnsConfig.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsUtil.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpDnsHitService.h"


// 我的修改 添加头文件
#import "HttpdnsgetNetworkInfoHelper.h"
#import "HttpdnsModel.h"

static NSURLSession *_scheduleCenterSession = nil;

@interface HttpdnsScheduleCenterRequest()<NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) dispatch_semaphore_t sem;

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
    _sem = dispatch_semaphore_create(0);

    return self;
}

- (NSDictionary *)queryScheduleCenterRecordFromServerSync {
    return [self queryScheduleCenterRecordFromServerSyncWithHostIndex:0];
}

- (NSDictionary *)queryScheduleCenterRecordFromServerSyncWithHostIndex:(NSInteger)hostIndex {
    
    NSDictionary *scheduleCenterRecord = nil;
    // 我的修改 判断是 SERVER_IP 还是 CENTER_IP
    NSArray *hostArray;
    if (ALICLOUD_HTTPDNS_SERVER_IP_BUTTON == NO) {
        hostArray = ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST;
    } else {
        hostArray = ALICLOUD_HTTPDNS_SERVER_IP_LIST;
    }
    
    NSInteger maxHostIndex = (hostArray.count - 1);
    if (hostIndex > maxHostIndex) {
        return nil;
    }
    
    NSError *error = nil;
    NSDate *methodStart = [NSDate date];
    
    // 这里发起请求 返回数据
    scheduleCenterRecord = [self queryScheduleCenterRecordFromServerWithHostIndex:hostIndex error:&error];
    
    // 我的修改 待测试 // 测试步骤 修改 .97 的 看会不会调用 .100 的
    if (!scheduleCenterRecord && error) {
        if (ALICLOUD_HTTPDNS_SERVER_IP_BUTTON == NO) {
            [self retryIndex:hostIndex + 1];
        }
        // 延迟 5 分钟再次 调用
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self retryIndex:hostIndex + 1];
            });
        });
    }
    
    // scheduleCenterRecord && !error
    BOOL success = (scheduleCenterRecord && !error);
    NSString *serverIpOrHost = [self scheduleCenterHostFromIPIndex:hostIndex];
    
    // 只在请求成功时统计耗
    [HttpDnsHitService hitSCTimeWithSuccess:success methodStart:methodStart url:serverIpOrHost];
    
    return scheduleCenterRecord;
}

- (void)retryIndex:(NSInteger)hostIndex{
    [self queryScheduleCenterRecordFromServerSyncWithHostIndex:hostIndex];
}


- (NSString *)scheduleCenterHostFromIPIndex:(NSInteger)index {
    
    NSString *serverHostOrIP = nil;
    NSArray *hostArray;
       
    // 我的修改 判断是 SERVER_IP 还是 CENTER_IP
    if (ALICLOUD_HTTPDNS_SERVER_IP_BUTTON == NO) {
        hostArray = ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST;
    } else {
        hostArray = ALICLOUD_HTTPDNS_SERVER_IP_LIST;
    }

    index = index % hostArray.count;
    serverHostOrIP = [HttpdnsUtil safeObjectAtIndexOrTheFirst:index array:hostArray defaultValue:nil];
    serverHostOrIP = [HttpdnsUtil getRequestHostFromString:serverHostOrIP];
    return serverHostOrIP;
}

/**
 * 我的修改 拼接 URL
 * https://203.107.1.1/100000/ss?region=hk&platform=ios&sdk_version=1.6.1&sid=LpmJIA2CUoi4&net=unknown&bssid=
 */
- (NSString *)constructRequestURLWithHostIndex:(NSInteger)hostIndex {
    
    NSString *serverIpOrHost = [self scheduleCenterHostFromIPIndex:hostIndex];
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSString * region = [self urlFormatRegion:sharedService.region];
    NSString *url = [NSString stringWithFormat:@"https://%@/%d/ss?%@platform=ios&sdk_version=%@",serverIpOrHost,sharedService.accountID,region,HTTPDNS_IOS_SDK_VERSION];
    url = [self urlFormatSidNetBssid:url];
    return url;
}

// 我的修改 url 添加 region
- (NSString *)urlFormatRegion:(NSString *)region {
    if ([HttpdnsUtil isValidString:region]) {
        return [NSString stringWithFormat:@"region=%@&",region];
    }
    return @"";
}

// 我的修改 url 添加 sid net 和 bssid
- (NSString *)urlFormatSidNetBssid:(NSString *)url {
    
    NSString *sessionId = [HttpdnsUtil generateSessionID];
    if ([HttpdnsUtil isValidString:sessionId]) {
        url = [NSString stringWithFormat:@"%@&sid=%@", url, sessionId];
    }

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
    return url;
}

// 我的修改 基于 URLSession 发送 HTTPS 请求
- (NSDictionary *)queryScheduleCenterRecordFromServerWithHostIndex:(NSInteger)hostIndex error:(NSError **)pError {
    
    NSString *fullUrlStr = [self constructRequestURLWithHostIndex:hostIndex];
    fullUrlStr = [fullUrlStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"`#%^{}\"[]|\\<> "].invertedSet];
    HttpdnsLogDebug("Request URL: %@", fullUrlStr);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:fullUrlStr]
                                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                          timeoutInterval:[HttpDnsService sharedInstance].timeoutInterval];
    __block NSDictionary * result = nil;
    __block NSError * errorStrong = nil;
    NSURLSessionTask *stTask = [_scheduleCenterSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            HttpdnsLogDebug("Network error: %@", error);
            errorStrong = error;
        } else {
            id jsonValue = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&errorStrong];
            result = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
            NSInteger statusCode = [(NSHTTPURLResponse *) response statusCode];
            if (statusCode != 200) {
                HttpdnsLogDebug("ReponseCode %ld.", (long)statusCode);
                if (errorStrong) {
                    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                                  @"Response code not 200, and parse response message error", @"ErrorMessage",
                                                  [NSString stringWithFormat:@"%ld", (long)statusCode], @"ResponseCode", nil];
                    errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10002 userInfo:dict];
                } else {
                    NSString *errCode = @"";
                    errCode = [HttpdnsUtil safeObjectForKey:@"code" dict:result];
                    NSDictionary *dict = nil;
                    if ([HttpdnsUtil isValidString:errCode]) {
                        dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        errCode, ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY, nil];
                    }
                    errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10003 userInfo:dict];
                }
            } else {
                HttpdnsLogDebug("Response code 200.");
            }
        }
        dispatch_semaphore_signal(_sem);
    }];
    [stTask resume];
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);

    if (!errorStrong) {
        if ([HttpdnsUtil isValidString:[result objectForKey:@"service_ip"]]) {
            ALICLOUD_HTTPDNS_SERVER_IP_LIST = [result objectForKey:@"service_ip"];
            ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED = [result objectForKey:@"service_ip"][0];
            ALICLOUD_HTTPDNS_SERVER_IP_BUTTON = YES;
        }
        return result;
    }
      
    if (pError != NULL) {
        *pError = errorStrong;
        NSURL *scAddrURL = [NSURL URLWithString:fullUrlStr];
        NSString *scAddrURLString = scAddrURL.host;
        [HttpDnsHitService bizhErrScWithScAddr:scAddrURLString errCode:errorStrong.code errMsg:errorStrong.description];
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
    // 我的修改 Domain host = 203.107.1.1
    NSString *host = @"203.107.1.1";
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
