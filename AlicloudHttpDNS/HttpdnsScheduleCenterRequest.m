//
//  HttpdnsScheduleCenterRequest.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/11.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsScheduleCenterRequest.h"
#import "HttpdnsLog.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsConstants.h"
#import "HttpdnsConfig.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsUtil.h"
#import "AlicloudHttpDNS.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpDnsHitService.h"

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
    NSArray *hostArray = ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST;
    NSInteger maxHostIndex = (hostArray.count - 1);
    if (hostIndex > maxHostIndex) {
        return nil;
    }
    NSError *error = nil;
//    CFAbsoluteTime methodStart = CFAbsoluteTimeGetCurrent();
    NSDate *methodStart = [NSDate date];
    scheduleCenterRecord = [self queryScheduleCenterRecordFromServerWithHostIndex:hostIndex error:&error];
    if (!scheduleCenterRecord && error) {
        return [self queryScheduleCenterRecordFromServerSyncWithHostIndex:(hostIndex + 1)];
    }
    //scheduleCenterRecord && !error
    BOOL success = (scheduleCenterRecord && !error);
    NSString *serverIpOrHost = [self scheduleCenterHostFromIPIndex:hostIndex];
    [HttpDnsHitService hitSCTimeWithSuccess:success methodStart:methodStart url:serverIpOrHost];
    return scheduleCenterRecord;
}

- (NSString *)scheduleCenterHostFromIPIndex:(NSInteger)index {
    NSString *serverHostOrIP = nil;
    NSArray *hostArray = ALICLOUD_HTTPDNS_SCHEDULE_CENTER_HOST_LIST;
    index = index % hostArray.count;

    @try {
        serverHostOrIP = hostArray[index];
    } @catch (NSException *exception) {
        serverHostOrIP = hostArray[0];
    }
    serverHostOrIP = [HttpdnsUtil getRequestHostFromString:serverHostOrIP];
    return serverHostOrIP;
}

/*!
 * 形如 https://106.11.90.200/sc/httpdns_config?account_id=153519&platform=ios&sdk_version=1.6.1
 */
- (NSString *)constructRequestURLWithHostIndex:(NSInteger)hostIndex {
    NSString *serverIpOrHost = [self scheduleCenterHostFromIPIndex:hostIndex];
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSString *url = [NSString stringWithFormat:@"https://%@/%@?account_id=%@&platform=ios&sdk_version=%@",
                     serverIpOrHost, ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_PATH, @(sharedService.accountID), HTTPDNS_IOS_SDK_VERSION];
    return url;
}

// 基于URLSession发送HTTPS请求
- (NSDictionary *)queryScheduleCenterRecordFromServerWithHostIndex:(NSInteger)hostIndex error:(NSError **)pError {
    NSString *fullUrlStr = [self constructRequestURLWithHostIndex:hostIndex];
    HttpdnsLogDebug("Request URL: %@", fullUrlStr);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:fullUrlStr]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:[HttpDnsService sharedInstance].timeoutInterval];
    
    __block NSDictionary *json = nil;
    __block NSError *errorStrong = nil;
    NSURLSessionTask *task = [_scheduleCenterSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            HttpdnsLogDebug("Network error: %@", error);
            errorStrong = error;
        } else {
             id jsonValue = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&errorStrong];
            json = [HttpdnsUtil getValidDictionaryFromJson:jsonValue];
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
                    @try {
                        errCode = [json objectForKey:@"code"];
                    } @catch (NSException *exception) {}
                    
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
    [task resume];
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);
    if (!errorStrong) {
        return json;
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
