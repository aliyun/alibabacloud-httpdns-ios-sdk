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
//"host";//查询的host
static NSString *const HTTPDNS_HIT_PARAM_SUCCESS = @"success" ;//返回的ip是否为空（成功=1，失败=0）
//ipv6" ;//是否ipv6，0为否，1位是
static NSString *const HTTPDNS_HIT_PARAM_CACHEOPEN = @"cacheOpen" ;//是否启用持久环缓存，0为关闭，1为启用

static NSString *const TRACKER_ID = @"httpdns";

//static NSString *const DEFAULT_LOAD_TYPE_VALUE = @"iOS";


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
    @try {
        [extProperties setObject:host forKey:HTTPDNS_HIT_PARAM_HOST];
        [extProperties setObject:scAddr forKey:HTTPDNS_HIT_PARAM_SCADDR];
        [extProperties setObject:[self srvAddrFromIndex:srvAddrIndex] forKey:HTTPDNS_HIT_PARAM_SRVADDR];
    } @catch (NSException *e) {}
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
    @try {
        [extProperties setObject:host forKey:HTTPDNS_HIT_PARAM_HOST];
        [extProperties setObject:scAddr forKey:HTTPDNS_HIT_PARAM_SCADDR];
        [extProperties setObject:[self srvAddrFromIndex:srvAddrIndex] forKey:HTTPDNS_HIT_PARAM_SRVADDR];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:HTTPDNS_BIZ_LOCAL_DISABLE duration:0 properties:extProperties];
}

+ (void)bizCacheEnable:(BOOL)enable {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:@(enable) forKey:HTTPDNS_HIT_PARAM_ENABLE];
        } @catch (NSException *e) {}
    [_tracker sendCustomHit:HTTPDNS_BIZ_CACHE duration:0 properties:extProperties];
}


+ (void)bizExpiredIpEnable:(BOOL)enable {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:@(enable) forKey:HTTPDNS_HIT_PARAM_ENABLE];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:HTTPDNS_BIZ_EXPIRED_IP duration:0 properties:extProperties];
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
    @try {
        [extProperties setObject:scAddr forKey:HTTPDNS_HIT_PARAM_SCADDR];
        [extProperties setObject:@(errCode) forKey:HTTPDNS_HIT_PARAM_ERRCODE];
        [extProperties setObject:errMsg forKey:HTTPDNS_HIT_PARAM_ERRMSG];
        [extProperties setObject:[self isIPV6Object] forKey:HTTPDNS_HIT_PARAM_IPV6];
    } @catch (NSException *e) {}
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
    @try {
        [extProperties setObject:[self srvAddrFromIndex:srvAddrIndex] forKey:HTTPDNS_HIT_PARAM_SRVADDR];
        [extProperties setObject:@(errCode) forKey:HTTPDNS_HIT_PARAM_ERRCODE];
        [extProperties setObject:errMsg forKey:HTTPDNS_HIT_PARAM_ERRMSG];
        [extProperties setObject:[self isIPV6Object] forKey:HTTPDNS_HIT_PARAM_IPV6];
    } @catch (NSException *e) {}
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
    @try {
        [extProperties setObject:log forKey:HTTPDNS_HIT_PARAM_LOG];
        [extProperties setObject:[self isIPV6Object] forKey:HTTPDNS_HIT_PARAM_IPV6];
    } @catch (NSException *e) {}
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
    @try {
        [extProperties setObject:log forKey:HTTPDNS_HIT_PARAM_LOG];
        [extProperties setObject:[self isIPV6Object] forKey:HTTPDNS_HIT_PARAM_IPV6];
    } @catch (NSException *e) {}
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
    @try {
        [extProperties setObject:exception forKey:HTTPDNS_HIT_PARAM_EXCEPTION];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:HTTPDNS_ERR_UNCAUGHT_EXCEPTION duration:0 properties:extProperties];
}

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
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:scAddr forKey:HTTPDNS_HIT_PARAM_SCADDR];
        [extProperties setObject:cost forKey:HTTPDNS_HIT_PARAM_COST];
        [extProperties setObject:[self isIPV6Object] forKey:HTTPDNS_HIT_PARAM_IPV6];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:HTTPDNS_PERF_SC duration:0 properties:extProperties];
}

+ (void)bizPerfSrcWithScAddr:(NSString *)scAddr
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
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:scAddr forKey:HTTPDNS_HIT_PARAM_SCADDR];
        [extProperties setObject:cost forKey:HTTPDNS_HIT_PARAM_COST];
        [extProperties setObject:[self isIPV6Object] forKey:HTTPDNS_HIT_PARAM_IPV6];
    } @catch (NSException *e) {}
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
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:host forKey:HTTPDNS_HIT_PARAM_HOST];
        [extProperties setObject:@(success) forKey:HTTPDNS_HIT_PARAM_SUCCESS];
        [extProperties setObject:@(cacheOpen) forKey:HTTPDNS_HIT_PARAM_CACHEOPEN];
        [extProperties setObject:[self isIPV6Object] forKey:HTTPDNS_HIT_PARAM_IPV6];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:HTTPDNS_PERF_GETIP duration:0 properties:extProperties];
}

+ (NSString *)srvAddrFromIndex:(NSInteger)index {
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    NSString *srv = [scheduleCenter getActivatedServerIPWithIndex:index];
    return srv;
}

+ (NSString *)scAddress {
    return ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP;
}

@end
