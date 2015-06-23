//
//  HttpdnsRequest.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsRequest.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"
#import "HttpdnsTokenGen.h"
#import "HttpdnsModel.h"

NSString * const HTTPDNS_SERVER_IP = @"10.125.65.207:8100";
NSString * const HTTPDNS_SERVER_BACKUP_HOST = @"";
NSString * const HTTPDNS_VERSION_NUM = @"1";

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

// 解析httpdns请求返回的结果
-(NSMutableArray *)parseHostInfoFromHttpResponse:(NSData *)body {
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:kNilOptions error:&error];
    if (!json) {
        return nil;
    }
    NSArray *dnss = [json objectForKey:@"dns"];
    for (NSDictionary *dict in dnss) {
        NSArray *ips = [dict objectForKey:@"ips"];
        NSMutableArray *ipNums = [[NSMutableArray alloc] init];
        for (NSDictionary *ipDict in ips) {
            [ipNums addObject:[ipDict objectForKey:@"ip"]];
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

// STS鉴权方式下构造httpdns解析请求头
-(NSMutableURLRequest *)constructRequestWith:(NSString *)hostsString withToken:(HttpdnsToken *)token {
    NSString *chooseEndpoint = degradeToHost ? HTTPDNS_SERVER_BACKUP_HOST : HTTPDNS_SERVER_IP;
    NSString *appId = [[HttpdnsTokenGen sharedInstance] appId];
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

    // 默认超时十五秒
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:url]
                                                      cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                  timeoutInterval:15];
    [request setHTTPMethod:@"GET"];
    [request setValue:signature forHTTPHeaderField:@"Authorization"];
    [request setValue:[token securityToken] forHTTPHeaderField:@"X-HTTPDNS-Security-Token"];

    return request;
}


// AK鉴权方式下构造httpdns解析请求头
-(NSMutableURLRequest *)constructRequestWith:(NSString *)hostsString {
    NSString *chooseEndpoint = degradeToHost ? HTTPDNS_SERVER_BACKUP_HOST : HTTPDNS_SERVER_IP;
    NSString *appId = TEST_APPID;
    NSString *timestamp = [HttpdnsRequest getCurrentTimeString];
    NSString *url = [NSString stringWithFormat:@"http://%@/resolve?host=%@&version=%@&appid=%@&timestamp=%@",
                     chooseEndpoint, hostsString, HTTPDNS_VERSION_NUM, appId, timestamp];
    NSString *contentToSign = [NSString stringWithFormat:@"%@%@%@%@",
                               HTTPDNS_VERSION_NUM, appId, timestamp, hostsString];
    NSString *signature = [NSString stringWithFormat:@"HTTPDNS %@:%@",
                           TEST_AK,
                           [HttpdnsUtil Base64HMACSha1Sign:[contentToSign dataUsingEncoding:NSUTF8StringEncoding] withKey:TEST_SK]];

    HttpdnsLogDebug(@"[constructRequest] - Request URL: %@", url);
    HttpdnsLogDebug(@"[constructRequest] - ContentToSign: %@", contentToSign);
    HttpdnsLogDebug(@"[constructRequest] - Signature: %@", signature);

    // 默认超时十五秒
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:url]
                                                      cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                  timeoutInterval:15];
    [request setHTTPMethod:@"GET"];
    [request setValue:signature forHTTPHeaderField:@"Authorization"];

    return request;
}

// 发起网络请求，解析域名，同步方法
-(NSMutableArray *)lookupAllHostsFromServer:(NSString *)hostsString error:(NSError **)error {
    HttpdnsLogDebug(@"[lookupAllHostFromServer] - ");
    HttpdnsToken *token = [[HttpdnsTokenGen sharedInstance] getToken];
    if (token == nil) {
        HttpdnsLogError(@"[lookupAllHostFromServer] - token is nil");
        NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:@"Token is null", @"ErrorMessage", nil];
        *error = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10001 userInfo:dict];
        return nil;
    }
    NSMutableURLRequest *request = [self constructRequestWith:hostsString withToken:token];

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
            return nil;
        }
        NSString *errCode = [json objectForKey:@"code"];
        if ([errCode caseInsensitiveCompare:@"RequestTimeTooSkewed"]) {
            [HttpdnsRequest requestServerTimeStamp];
        }
        return nil;
    }

    HttpdnsLogDebug(@"[lookupAllHostFromServer] - No network error occur.");
    return [self parseHostInfoFromHttpResponse:result];
}

+(void)requestServerTimeStamp {
    NSString *chooseEndpoint = degradeToHost ? HTTPDNS_SERVER_BACKUP_HOST : HTTPDNS_SERVER_IP;
    NSString *timeUrl = [NSString stringWithFormat:@"http://%@/timestamp", chooseEndpoint];
    // 默认超时十五秒
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:timeUrl]
                                                      cachePolicy:NSURLRequestUseProtocolCachePolicy
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
    [failedCntLock lock];
    if (degradeToHost) {
        // 已经降级，暂时不再做处理
        return;
    }
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