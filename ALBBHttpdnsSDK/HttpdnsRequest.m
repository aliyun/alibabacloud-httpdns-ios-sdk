//
//  HttpdnsRequest.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsServiceProvider.h"
#import "HttpdnsModel.h"
#import "HttpdnsRequest.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"
#import "HttpdnsConfig.h"

#ifdef IS_DPA_RELEASE
#import <UTMini/UTAnalytics.h>
#import <UTMini/UTBaseRequestAuthentication.h>
#import <UTMini/UTOirginalCustomHitBuilder.h>

static BOOL reported = false;
#endif

NSString * const HTTPDNS_SERVER_IP = @"140.205.143.143";
NSString * const HTTPDNS_SERVER_BACKUP_HOST = @"httpdns.aliyuncs.com";
NSString * const HTTPDNS_VERSION_NUM = @"1";

static NSString *SDKNAME = @"HTTPDNS-IOS";
static NSString *operationalDataEventID = @"66681";

NSString * const TEST_AK = @"httpdnstest";
NSString * const TEST_SK = @"hello";
NSString * const TEST_APPID = @"123456";

static BOOL degradeToHost = NO;
static NSLock *failedCntLock;
static int accumulateFailedCount = 0;
static long long headmostFailedTime = 0;

static long long relativeTimeVal = 0;
static NSLock * rltTimeLock = nil;

@implementation HttpdnsRequest
#pragma mark init

+(void)initialize {
    failedCntLock = [[NSLock alloc] init];
    rltTimeLock = [[NSLock alloc] init];
}

-(instancetype)init {
    return self;
}

#pragma mark LookupIpAction

-(NSMutableArray *)parseHostInfoFromHttpResponse:(NSData *)body {
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:kNilOptions error:&error];
    if (json == nil) {
        return nil;
    }
    NSArray *dnss = [json objectForKey:@"dns"];
    if (dnss == nil) {
        return nil;
    }
    for (NSDictionary *dict in dnss) {
        NSArray *ips = [dict objectForKey:@"ips"];
        if (ips == nil) {
            continue;
        }
        NSMutableArray *ipNums = [[NSMutableArray alloc] init];
        for (NSDictionary *ipDict in ips) {
            HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
            [ipObject setIp:[ipDict objectForKey:@"ip"]];
            [ipNums addObject:ipObject];
        }
        HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
        [hostObject setHostName:[dict objectForKey:@"host"]];
        [hostObject setIps:ipNums];
        [hostObject setTTL:[[dict objectForKey:@"ttl"] longLongValue]];
        [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
        [hostObject setState:VALID];
        HttpdnsLogDebug(@"[parseResponse] - host: %@ ttl: %lld ips: %@", [hostObject getHostName], [hostObject getTTL], ipNums);
        [result addObject:hostObject];
    }
    return result;
}

#ifdef IS_DPA_RELEASE
// STS鉴权方式下构造httpdns解析请求头
-(NSMutableURLRequest *)constructRequestWith:(NSString *)hostsString withToken:(HttpdnsToken *)token {
    NSString *chooseEndpoint = degradeToHost ? HTTPDNS_SERVER_BACKUP_HOST : HTTPDNS_SERVER_IP;
    NSString *appId = [token appId];
    NSString *timestamp = [HttpdnsRequest getCurrentTimeString];
    NSString *url = [NSString stringWithFormat:@"http://%@/resolve?host=%@&version=%@&appid=%@&timestamp=%@",
                     chooseEndpoint, hostsString, HTTPDNS_VERSION_NUM, appId, timestamp];
    NSString *contentToSign = [NSString stringWithFormat:@"%@%@%@%@%@",
                               HTTPDNS_VERSION_NUM, appId, timestamp, hostsString, [token securityToken]];

    NSString *signature = [NSString stringWithFormat:@"HTTPDNS %@:%@",
                           [token accessKeyId],
                           [HttpdnsUtil Base64HMACSha1Sign:[contentToSign dataUsingEncoding:NSUTF8StringEncoding] withKey:[token accessKeySecret]]];

    HttpdnsLogDebug(@"[constructRequest] - Request URL: %@", url);
    HttpdnsLogDebug(@"[constructRequest] - ContentToSign: %@", contentToSign);
    HttpdnsLogDebug(@"[constructRequest] - Signature: %@", signature);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:url]
                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                  timeoutInterval:15];
    [request setHTTPMethod:@"GET"];
    [request setValue:signature forHTTPHeaderField:@"Authorization"];
    [request setValue:[token securityToken] forHTTPHeaderField:@"X-HTTPDNS-Security-Token"];

    return request;
}
#endif


// AK鉴权方式下构造httpdns解析请求头
-(NSMutableURLRequest *)constructRequestWith:(NSString *)hostsString {
    HttpDnsServiceProvider * sharedService = [HttpDnsServiceProvider sharedInstance];

    NSString *chooseEndpoint = degradeToHost ? HTTPDNS_SERVER_BACKUP_HOST : HTTPDNS_SERVER_IP;
    NSString *appId = sharedService.appId;
    NSString *timestamp = [HttpdnsRequest getCurrentTimeString];
    NSString *url = [NSString stringWithFormat:@"http://%@/resolve?host=%@&version=%@&appid=%@&timestamp=%@",
                     chooseEndpoint, hostsString, HTTPDNS_VERSION_NUM, appId, timestamp];
    NSString *contentToSign = [NSString stringWithFormat:@"%@%@%@%@",
                               HTTPDNS_VERSION_NUM, appId, timestamp, hostsString];

    id<HttpdnsCredentialProvider> credentialProvider = sharedService.credentialProvider;
    NSString *signature = [credentialProvider sign:contentToSign];

    HttpdnsLogDebug(@"[constructRequest] - 1. Request URL: %@", url);
    HttpdnsLogDebug(@"[constructRequest] - 2. ContentToSign: %@", contentToSign);
    HttpdnsLogDebug(@"[constructRequest] - 3. Signature: %@", signature);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:url]
                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                  timeoutInterval:15];
    [request setHTTPMethod:@"GET"];
    [request setValue:signature forHTTPHeaderField:@"Authorization"];

    return request;
}

-(NSMutableArray *)lookupAllHostsFromServer:(NSString *)hostsString error:(NSError **)error {
    HttpdnsLogDebug(@"[lookupAllHostFromServer] - ");

#ifdef IS_DPA_RELEASE
    HttpdnsToken *token = [[HttpdnsTokenGen sharedInstance] getToken];
    if (token == nil) {
        HttpdnsLogError(@"[lookupAllHostFromServer] - token is nil");
        NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:@"Token is null", @"ErrorMessage", nil];
        *error = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10001 userInfo:dict];
        sleep(2); // 如果拿不到token，很可能是因为刚启动，所以等待2秒钟以后再重试。
        return nil;
    }
    if (!reported) {
        reported = YES;
        UTOirginalCustomHitBuilder *customHitBuilder = [[UTOirginalCustomHitBuilder alloc] init];
        [customHitBuilder setEventId:operationalDataEventID];
        [customHitBuilder setArg1:SDKNAME];
        [customHitBuilder setArg2:HTTPDNS_IOS_SDK_VERSION];
        UTTracker *lTracker = [[UTAnalytics getInstance] getTracker:@"aliyun_dpa"];
        NSDictionary *dic = [customHitBuilder build];
        [lTracker send:dic];
    }
    NSMutableURLRequest *request = [self constructRequestWith:hostsString withToken:token];
#else
    NSMutableURLRequest *request = [self constructRequestWith:hostsString];
#endif

    NSHTTPURLResponse *response;
    NSData *result = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error];

    // 异常交由上层处理
    if (*error) {
        HttpdnsLogError(@"[lookupAllHostFromServer] - Network error. error %@", *error);
        return nil;
    } else if ([response statusCode] != 200) {
        HttpdnsLogError(@"[lookupAllHostFromServer] - ReponseCode not 200, but %ld.", (long)[response statusCode]);
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:result options:kNilOptions error:error];
        if (*error) {
            NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  @"Response code not 200, and parse response message error", @"ErrorMessage",
                                  [NSString stringWithFormat:@"%d", (int) [response statusCode]], @"ResponseCode", nil];
            *error = [[NSError alloc] initWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10002 userInfo:dict];
            return nil;
        }
        NSString *errCode = [json objectForKey:@"code"];
        if ([errCode caseInsensitiveCompare:@"RequestTimeTooSkewed"]) {
            [HttpdnsRequest requestServerTimeStamp];
        }
        NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                              errCode, @"ErrorMessage", nil];
        *error = [[NSError alloc] initWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10003 userInfo:dict];
        return nil;
    }

    HttpdnsLogDebug(@"[lookupAllHostFromServer] - Response code 200.");
    return [self parseHostInfoFromHttpResponse:result];
}

+(void)requestServerTimeStamp {
    NSString *chooseEndpoint = degradeToHost ? HTTPDNS_SERVER_BACKUP_HOST : HTTPDNS_SERVER_IP;
    NSString *timeUrl = [NSString stringWithFormat:@"http://%@/timestamp", chooseEndpoint];
    // 默认超时十五秒
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:timeUrl]
                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                  timeoutInterval:15];
    NSHTTPURLResponse *response;
    NSError *error;
    NSData *result = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    if (error || [response statusCode] != 200) {
        return;
    }
    NSString *timestamp = [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
    [HttpdnsRequest updateTimeRelativeValWithBase:[timestamp longLongValue]];
}

+(void)notifyRequestFailed {
    if (degradeToHost) {
        // 已经降级，暂时不再做处理
        return;
    }
    [failedCntLock lock];
    long long currentTime = [HttpdnsUtil currentEpochTimeInSecond];
    if (accumulateFailedCount == 0) {
        headmostFailedTime = currentTime;
    }
    if (accumulateFailedCount > 4) {
        if (currentTime - headmostFailedTime < 60) {
            degradeToHost = YES;
        } else {
            headmostFailedTime = currentTime;
        }
        accumulateFailedCount = 0;
    }
    accumulateFailedCount++;
    [failedCntLock unlock];
}

+(void)updateTimeRelativeValWithBase:(long long)baseTime {
    [rltTimeLock lock];
    relativeTimeVal = baseTime - [HttpdnsUtil currentEpochTimeInSecond];
    HttpdnsLogDebug(@"[updateTimeRelativeValWithBase] - reletiveTime: %lld, sysTime: %lld", relativeTimeVal, [HttpdnsUtil currentEpochTimeInSecond]);
    [rltTimeLock unlock];
}

+(NSString *)getCurrentTimeString {
    long long sysCurrent = [HttpdnsUtil currentEpochTimeInSecond];
    [rltTimeLock lock];
    long long realCurrent = sysCurrent + relativeTimeVal;
    [rltTimeLock unlock];
    return [NSString stringWithFormat:@"%lld", realCurrent];
}
@end