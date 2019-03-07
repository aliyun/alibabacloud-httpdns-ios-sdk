//
//  
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/11.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AlicloudUtils/AlicloudTrackerManager.h>
#import <AlicloudUtils/AlicloudTracker.h>
#import "HttpDnsHitService.h"
//#import "HFXStore.h"
#import "AlicloudHttpDNS.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsConstants.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsConstants.h"
#import "UIApplication+ABSHTTPDNSSetting.h"

static NSString *const HTTPDNS_BIZ_ACTIVE = @"biz_active";

static NSString *const HTTPDNS_BIZ_SNIFFER = @"biz_sniffer";
static NSString *const HTTPDNS_HIT_PARAM_HOST = @"host" ;//查询的HOST
static NSString *const HTTPDNS_HIT_PARAM_SCADDR = @"scAddr" ;//当前SC服务器地址
static NSString *const HTTPDNS_HIT_PARAM_SRVADDR = @"srvAddr" ;//当前嗅探的HTTPDNS服务器地址

static NSString *const HTTPDNS_BIZ_LOCAL_DISABLE = @"biz_local_disable";
//HOST" ;//查询的HOST
//scAddr" ;//当前SC服务器地址
//SRVADDR" ;//当前嗅探的HTTPDNS服务器地址

static NSString *const HTTPDNS_BIZ_CACHE = @"biz_cache";
static NSString *const HTTPDNS_HIT_PARAM_ENABLE = @"enable" ;//是否启用持久环缓存，0为关闭，1为启用

static NSString *const HTTPDNS_BIZ_EXPIRED_IP = @"biz_expired_ip";
//enable" ;//是否允许过期ip，0为不允许，1为允许

static NSString *const HTTPDNS_ERR_SC = @"err_sc";
//scAddr" ;//SC服务器ip/host
static NSString *const HTTPDNS_HIT_PARAM_ERRCODE = @"errCode" ;//错误码
static NSString *const HTTPDNS_HIT_PARAM_ERRMSG = @"errMsg" ;//错误信息
static NSString *const HTTPDNS_HIT_PARAM_IPV6 = @"ipv6" ;//是否ipv6，0为否，1位是


static NSString *const HTTPDNS_ERR_SRV = @"err_srv";
//srvAddr" ;//httpdns服务器地址
//errCode" ;//错误码
//errMsg" ;//错误信息
//ipv6" ;//是否ipv6，0为否，1位是

static NSString *const HTTPDNS_ERR_CONTINUOUS_BOOTING_CRASH = @"err_continuous_booting_crash";
static NSString *const HTTPDNS_HIT_PARAM_LOG = @"log" ;//异常日志
//ipv6" ;//是否ipv6，0为否，1位是

static NSString *const HTTPDNS_ERR_CONTINUOUS_RUNNING_CRASH = @"err_continuous_running_crash";
//log	 ;//异常日志，exception信息
//ipv6" ;//是否ipv6，0为否，1位是

static NSString *const HTTPDNS_ERR_UNCAUGHT_EXCEPTION = @"err_uncaught_exception";
static NSString *const HTTPDNS_HIT_PARAM_EXCEPTION = @"exception" ;//异常信息

static NSString *const HTTPDNS_PERF_SC = @"perf_sc";
//scAddr" ;//SC服务器地址
static NSString *const HTTPDNS_HIT_PARAM_COST = @"cost" ;//请求耗时(ms)
//ipv6" ;//是否ipv6，0为否，1位是

static NSString *const HTTPDNS_PERF_SRV = @"perf_srv";
//srvAddr" ;//httpdns服务器地址
//cost" ;//请求耗时(ms)
//ipv6" ;//是否ipv6，0为否，1位是

static NSString *const HTTPDNS_PERF_GETIP = @"perf_getip";
static NSString *const HTTPDNS_PERF_USER_GETIP = @"perf_user_getip";

//"host";//查询的host
static NSString *const HTTPDNS_HIT_PARAM_SUCCESS = @"success" ;//返回的ip是否为空（成功=1，失败=0）
//ipv6" ;//是否ipv6，0为否，1位是
static NSString *const HTTPDNS_HIT_PARAM_CACHEOPEN = @"cacheOpen" ;//是否启用持久环缓存，0为关闭，1为启用





static NSString *const TRACKER_ID = @"httpdns";

static NSString *const HTTPDNS_HIT_PARAM_DEFAULTIP = @"defaultIp";
static NSString *const HTTPDNS_HIT_PARAM_SELECTEDIP = @"selectedIp";
static NSString *const HTTPDNS_HIT_PARAM_DEFAULTIPCOST = @"defaultIpCost";
static NSString *const HTTPDNS_HIT_PARAM_SELECTEDIPCOST = @"selectedIpCost";
static NSString *const HTTPDNS_HIT_PARAM_IPCOUNT = @"ipCount";
static NSString *const HTTPDNS_PERF_IPSELECTION = @"perf_ipselection";

static AlicloudTracker *_tracker;
static BOOL _disableStatus = NO;

@implementation HttpDnsHitService

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _tracker = [[AlicloudTrackerManager getInstance] getTrackerBySdkId:TRACKER_ID version:HTTPDNS_IOS_SDK_VERSION];
    });
}

+ (void)setGlobalPropertyWithAccountId:(NSString *)accountId {
    /* set global property */
    if ([HttpdnsUtil isValidString:accountId]) {
        [_tracker setGlobalProperty:@"accountId" value:accountId];
    }
}

+ (void)disableHitService {
    _disableStatus = YES;
}

+ (void)bizActiveHit {
    if (_disableStatus) {
        return;
    }
    [_tracker sendCustomHit:HTTPDNS_BIZ_ACTIVE duration:0 properties:nil];
}

+ (void)bizSnifferWithHost:(NSString *)host
              srvAddrIndex:(NSInteger)srvAddrIndex {
    if (![HttpdnsUtil isValidString:host]) {
        return;
    }
    [self bizSnifferWithHost:host scAddr:[self scAddress] srvAddrIndex:srvAddrIndex];
}

+ (void)bizSnifferWithHost:(NSString *)host
                    scAddr:(NSString *)scAddr
                   srvAddrIndex:(NSInteger)srvAddrIndex {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:host]) {
        return;
    }
    if (![HttpdnsUtil isValidString:scAddr]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:host key:HTTPDNS_HIT_PARAM_HOST toDict:extProperties];
    [HttpdnsUtil safeAddValue:scAddr key:HTTPDNS_HIT_PARAM_SCADDR toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self srvAddrFromIndex:srvAddrIndex] key:HTTPDNS_HIT_PARAM_SRVADDR toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_BIZ_SNIFFER duration:0 properties:extProperties];
}

+ (void)bizLocalDisableWithHost:(NSString *)host
                   srvAddrIndex:(NSInteger)srvAddrIndex {
    if (![HttpdnsUtil isValidString:host]) {
        return;
    }
    [self bizLocalDisableWithHost:host scAddr:[self scAddress] srvAddrIndex:srvAddrIndex];
}

+ (void)bizLocalDisableWithHost:(NSString *)host
                    scAddr:(NSString *)scAddr
                   srvAddrIndex:(NSInteger)srvAddrIndex {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:host]) {
        return;
    }
    if (![HttpdnsUtil isValidString:scAddr]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:host key:HTTPDNS_HIT_PARAM_HOST toDict:extProperties];
    [HttpdnsUtil safeAddValue:scAddr key:HTTPDNS_HIT_PARAM_SCADDR toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self srvAddrFromIndex:srvAddrIndex] key:HTTPDNS_HIT_PARAM_SRVADDR toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_BIZ_LOCAL_DISABLE duration:0 properties:extProperties];
}

+ (void)bizCacheEnable:(BOOL)enable {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:@(enable) key:HTTPDNS_HIT_PARAM_ENABLE toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_BIZ_CACHE duration:0 properties:extProperties];
}


+ (void)bizExpiredIpEnable:(BOOL)enable {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:@(enable) key:HTTPDNS_HIT_PARAM_ENABLE toDict:extProperties];

    [_tracker sendCustomHit:HTTPDNS_BIZ_EXPIRED_IP duration:0 properties:extProperties];
}

+ (BOOL)isIPv6OnlyNetwork {
    return [[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork];
}

+ (NSNumber *)isIPV6Object {
    return @([[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork]);
}

+ (void)bizhErrScWithScAddr:(NSString *)scAddr
                          errCode:(NSInteger)errCode
                           errMsg:(NSString *)errMsg {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:errMsg]) {
        return;
    }
    if (![HttpdnsUtil isValidString:scAddr]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:scAddr key:HTTPDNS_HIT_PARAM_SCADDR toDict:extProperties];
    [HttpdnsUtil safeAddValue:@(errCode) key:HTTPDNS_HIT_PARAM_ERRCODE toDict:extProperties];
    [HttpdnsUtil safeAddValue:errMsg key:HTTPDNS_HIT_PARAM_ERRMSG toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self isIPV6Object] key:HTTPDNS_HIT_PARAM_IPV6 toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_ERR_SC duration:0 properties:extProperties];
}

+ (void)bizErrSrvWithSrvAddrIndex:(NSInteger)srvAddrIndex
                          errCode:(NSInteger)errCode
                           errMsg:(NSString *)errMsg {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:errMsg]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:[self srvAddrFromIndex:srvAddrIndex] key:HTTPDNS_HIT_PARAM_SRVADDR toDict:extProperties];
    [HttpdnsUtil safeAddValue:@(errCode) key:HTTPDNS_HIT_PARAM_ERRCODE toDict:extProperties];
    [HttpdnsUtil safeAddValue:errMsg key:HTTPDNS_HIT_PARAM_ERRMSG toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self isIPV6Object] key:HTTPDNS_HIT_PARAM_IPV6 toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_ERR_SRV duration:0 properties:extProperties];
}


+ (void)bizContinuousBootingCrashWithLog:(NSString *)log {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:log]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:log key:HTTPDNS_HIT_PARAM_LOG toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self isIPV6Object] key:HTTPDNS_HIT_PARAM_IPV6 toDict:extProperties];

    [_tracker sendCustomHit:HTTPDNS_ERR_CONTINUOUS_BOOTING_CRASH duration:0 properties:extProperties];
}

+ (void)bizRunningCrashWithLog:(NSString *)log {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:log]) {
        return;
    }

    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:log key:HTTPDNS_HIT_PARAM_LOG toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self isIPV6Object] key:HTTPDNS_HIT_PARAM_IPV6 toDict:extProperties];

    [_tracker sendCustomHit:HTTPDNS_ERR_CONTINUOUS_RUNNING_CRASH duration:0 properties:extProperties];
}

+ (void)bizUncaughtExceptionWithException:(NSString *)exception {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:exception]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:exception key:HTTPDNS_HIT_PARAM_EXCEPTION toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_ERR_UNCAUGHT_EXCEPTION duration:0 properties:extProperties];
}

/*
* 只在成功时上报耗时数据
*/
+ (void)bizPerfScWithScAddr:(NSString *)scAddr
                    cost:(NSString *)cost {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:cost]) {
        return;
    }
    if (![HttpdnsUtil isValidString:scAddr]) {
        return;
    }
    if ([self isIPv6OnlyNetwork]) {
        return;
    }
    if (![self isAbleToHit]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:scAddr key:HTTPDNS_HIT_PARAM_SCADDR toDict:extProperties];
    [HttpdnsUtil safeAddValue:cost key:HTTPDNS_HIT_PARAM_COST toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self isIPV6Object] key:HTTPDNS_HIT_PARAM_IPV6 toDict:extProperties];
    [HttpdnsUtil safeAddValue:@(YES) key:HTTPDNS_HIT_PARAM_SUCCESS toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_PERF_SC duration:0 properties:extProperties];
}

+ (void)hitSRVTimeWithSuccess:(BOOL)success methodStart:(NSDate *)methodStart url:(NSString *)url {
    NSTimeInterval costTime = -([methodStart timeIntervalSinceNow] * 1000);
    BOOL timeValid = [self isValidForCostTime:costTime];
    if (timeValid && success) {
        //只在请求成功时统计耗时
        NSString *time = [NSString stringWithFormat:@"%@", @(costTime)];
        HttpdnsLogDebug("Resolve host(%@) over network use time %@ ms.", url, time);
        [HttpDnsHitService bizPerfSrcWithSrvAddr:url cost:time];
    }
}

+ (void)hitSCTimeWithSuccess:(BOOL)success methodStart:(NSDate *)methodStart url:(NSString *)url {
    //只在请求成功时统计耗时
    NSTimeInterval costTime = -([methodStart timeIntervalSinceNow] * 1000);
    BOOL timeValid = [self isValidForCostTime:costTime];
    if (timeValid && success) {
        NSString *serverIpOrHost = url;
        NSString *time = [NSString stringWithFormat:@"%@", @(costTime)];
        HttpdnsLogDebug("SC (%@) use time %@ ms.", serverIpOrHost, time);
        [HttpDnsHitService bizPerfScWithScAddr:serverIpOrHost cost:time];
    }
}

+ (BOOL)isValidForCostTime:(NSTimeInterval)costTime {
    //只在请求成功时统计耗时
    NSTimeInterval timeout = (([HttpDnsService sharedInstance].timeoutInterval > 0) ?: 15.0 ) * 1000;
    BOOL timeValid = ((costTime > 0) && (costTime < timeout));
    return timeValid;
}

/*
 * 只在成功时上报耗时数据
 */
+ (void)bizPerfSrcWithSrvAddr:(NSString *)srvAddr
                       cost:(NSString *)cost {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:cost]) {
        return;
    }
    if (![HttpdnsUtil isValidString:srvAddr]) {
        return;
    }
    if ([self isIPv6OnlyNetwork]) {
        return;
    }
    if (![self isAbleToHit]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:srvAddr key:HTTPDNS_HIT_PARAM_SCADDR toDict:extProperties];
    [HttpdnsUtil safeAddValue:cost key:HTTPDNS_HIT_PARAM_COST toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self isIPV6Object] key:HTTPDNS_HIT_PARAM_IPV6 toDict:extProperties];
    [HttpdnsUtil safeAddValue:@(YES) key:HTTPDNS_HIT_PARAM_SUCCESS toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_PERF_SRV duration:0 properties:extProperties];
}

+ (void)bizPerfGetIPWithHost:(NSString *)host
                     success:(BOOL)success
                   cacheOpen:(BOOL)cacheOpen {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:host]) {
        return;
    }
    if ([self isIPv6OnlyNetwork]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:host key:HTTPDNS_HIT_PARAM_HOST toDict:extProperties];
    [HttpdnsUtil safeAddValue:@(success) key:HTTPDNS_HIT_PARAM_SUCCESS toDict:extProperties];
    [HttpdnsUtil safeAddValue:@(cacheOpen) key:HTTPDNS_HIT_PARAM_CACHEOPEN toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self isIPV6Object] key:HTTPDNS_HIT_PARAM_IPV6 toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_PERF_GETIP duration:0 properties:extProperties];
}

+ (void)bizPerfUserGetIPWithHost:(NSString *)host
                     success:(BOOL)success
                   cacheOpen:(BOOL)cacheOpen {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:host]) {
        return;
    }
    if ([self isIPv6OnlyNetwork]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:host key:HTTPDNS_HIT_PARAM_HOST toDict:extProperties];
    [HttpdnsUtil safeAddValue:@(success) key:HTTPDNS_HIT_PARAM_SUCCESS toDict:extProperties];
    [HttpdnsUtil safeAddValue:@(cacheOpen) key:HTTPDNS_HIT_PARAM_CACHEOPEN toDict:extProperties];
    [HttpdnsUtil safeAddValue:[self isIPV6Object] key:HTTPDNS_HIT_PARAM_IPV6 toDict:extProperties];

    [_tracker sendCustomHit:HTTPDNS_PERF_USER_GETIP duration:0 properties:extProperties];
}

+ (void)bizIPSelectionWithHost:(NSString *)host
                     defaultIp:(NSString *)defaultIp
                   selectedIp:(NSString *)selectedIp
                defaultIpCost:(NSNumber *)defaultIpCost
               selectedIpCost:(NSNumber *)selectedIpCost
                       ipCount:(NSNumber *)ipCount {
    if (_disableStatus) {
        return;
    }
    if (![HttpdnsUtil isValidString:host]) {
        return;
    }
    if (![HttpdnsUtil isValidString:defaultIp]) {
        return;
    }
    if (![HttpdnsUtil isValidString:selectedIp]) {
        return;
    }
    if ([defaultIpCost integerValue] <= [selectedIpCost integerValue]) {
        return;
    }
    if ([self isIPv6OnlyNetwork]) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    [HttpdnsUtil safeAddValue:host key:HTTPDNS_HIT_PARAM_HOST toDict:extProperties];
    [HttpdnsUtil safeAddValue:defaultIp key:HTTPDNS_HIT_PARAM_DEFAULTIP toDict:extProperties];
    [HttpdnsUtil safeAddValue:selectedIp key:HTTPDNS_HIT_PARAM_SELECTEDIP toDict:extProperties];
    [HttpdnsUtil safeAddValue:defaultIpCost key:HTTPDNS_HIT_PARAM_DEFAULTIPCOST toDict:extProperties];
    [HttpdnsUtil safeAddValue:selectedIpCost key:HTTPDNS_HIT_PARAM_SELECTEDIPCOST toDict:extProperties];
    [HttpdnsUtil safeAddValue:ipCount key:HTTPDNS_HIT_PARAM_SUCCESS toDict:extProperties];
    [_tracker sendCustomHit:HTTPDNS_PERF_IPSELECTION duration:0 properties:extProperties];
    
}
+ (NSString *)srvAddrFromIndex:(NSInteger)index {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    NSString *srv = [scheduleCenter getActivatedServerIPWithIndex:index];
    return srv;
}

+ (NSString *)scAddress {
    return ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP;
}

+ (BOOL)isAbleToHit {
    if ([AlicloudReachabilityManager shareInstance].currentNetworkStatus != AlicloudReachableViaWiFi) {
        return NO;
    }
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    if (!sharedService.accountID || sharedService.accountID == 0) {
        return NO;
    }
    return YES;
}

@end
