//
//  AlicloudReachabilityManager.m
//
//  Created by 亿刀 on 14-1-9.
//  Edited by junmo on 15-5-16
//  Copyright (c) 2014年 Twitter. All rights reserved.
//

#import "HttpdnsReachabilityManager.h"
#import "HttpdnsIPv6Adapter.h"
#import <arpa/inet.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreTelephony/CTCarrier.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <sys/socket.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UIKit/UIDevice.h>
#import "HttpdnsLog_Internal.h"

static char *const SPDYReachabilityQueue = "com.alibaba.NetworkSDKReachabilityQueue";
static dispatch_queue_t reachabilityQueue;
static NSString *const CHECK_HOSTNAME = @"www.taobao.com";

static CTTelephonyNetworkInfo *networkInfo;

@implementation HttpdnsReachabilityManager
{
    AlicloudNetworkStatus          _currentNetworkStatus;
    AlicloudNetworkStatus              _preNetworkStatus;
    SCNetworkReachabilityRef            _reachabilityRef;
}

+ (HttpdnsReachabilityManager *)shareInstance {
    return [HttpdnsReachabilityManager getInstanceWithNetInfo:nil];
}

+ (HttpdnsReachabilityManager *)shareInstanceWithNetInfo:(CTTelephonyNetworkInfo *)netInfo {
    return [HttpdnsReachabilityManager getInstanceWithNetInfo:netInfo];
}

+ (HttpdnsReachabilityManager *)getInstanceWithNetInfo:(CTTelephonyNetworkInfo *)netInfo {
    static id singletonInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!singletonInstance) {
            singletonInstance = [[super allocWithZone:NULL] initWithNetInfo:netInfo];
        }
    });
    return singletonInstance;
}

+ (id)allocWithZone:(struct _NSZone *)zone {
    return [self shareInstance];
}

- (id)copyWithZone:(struct _NSZone *)zone {
    return self;
}

- (id)initWithNetInfo:(CTTelephonyNetworkInfo *)netInfo {
    self = [super init];
    if (self) {
        _reachabilityRef =  SCNetworkReachabilityCreateWithName(NULL, [CHECK_HOSTNAME UTF8String]);
        if (!networkInfo) {
            if (netInfo) {
                networkInfo = netInfo;
            } else {
                networkInfo = [[CTTelephonyNetworkInfo alloc] init];
            }
        }
        //开始监控网络变化
        [self _startNotifier];
    }

    return self;
}

- (SCNetworkReachabilityRef)_createReachabilityRef:(CFAllocatorRef)allocator {
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    return SCNetworkReachabilityCreateWithAddress(allocator, (const struct sockaddr*)&zeroAddress);
}

- (BOOL)_startNotifier
{
    if (!_reachabilityRef)
    {
        _reachabilityRef =  SCNetworkReachabilityCreateWithName(NULL, [CHECK_HOSTNAME UTF8String]);
    }

    if (_reachabilityRef)
    {
        SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};

        if (SCNetworkReachabilitySetCallback(_reachabilityRef, ReachabilityCallback, &context))
        {
            reachabilityQueue = dispatch_queue_create(SPDYReachabilityQueue, DISPATCH_QUEUE_SERIAL);
            SCNetworkReachabilitySetDispatchQueue(_reachabilityRef, reachabilityQueue);
            return YES;
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self _reachabilityStatus];
        });
    }

    return NO;
}

- (AlicloudNetworkStatus)currentNetworkStatus
{
    if (!_currentNetworkStatus) {
        [self _reachabilityStatus];
    }
    return _currentNetworkStatus;
}

- (AlicloudNetworkStatus)preNetworkStatus
{
    return _preNetworkStatus;
}

- (AlicloudNetworkStatus)_reachabilityStatus
{
    if (_reachabilityRef)
    {
        SCNetworkReachabilityFlags flags = 0;
        if (SCNetworkReachabilityGetFlags(_reachabilityRef, &flags))
        {
            [self updateCurStatus:[self _networkStatusForReachabilityFlags:flags]];
        }
    }
    return _currentNetworkStatus;
}

- (BOOL)isReachableViaWifi {

    if (_reachabilityRef) {
        SCNetworkReachabilityFlags flags = 0;
        if (SCNetworkReachabilityGetFlags(_reachabilityRef, &flags)) {
            if ((flags & kSCNetworkReachabilityFlagsReachable)) {
                if(flags & kSCNetworkReachabilityFlagsIsWWAN) {
                    return NO;
                }
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)isReachableViaWWAN {
    if (_reachabilityRef) {
        SCNetworkReachabilityFlags flags = 0;
        if (SCNetworkReachabilityGetFlags(_reachabilityRef, &flags)) {
            if ((flags & kSCNetworkReachabilityFlagsReachable)) {
                if(flags & kSCNetworkReachabilityFlagsIsWWAN) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

- (void)updateCurStatus:(AlicloudNetworkStatus)status {
    _preNetworkStatus = _currentNetworkStatus;
    _currentNetworkStatus = status;
}

- (BOOL)checkInternetConnection {
    SCNetworkReachabilityRef defaultRouteReachability = SCNetworkReachabilityCreateWithName(NULL, [CHECK_HOSTNAME UTF8String]);
    SCNetworkReachabilityFlags flags;

    BOOL didRetrieveFlags = SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);

    CFRelease(defaultRouteReachability);

    if (!didRetrieveFlags)
    {
        return NO;
    }

    BOOL isReachable = flags & kSCNetworkFlagsReachable;
    BOOL needsConnection = flags & kSCNetworkFlagsConnectionRequired;

    return (isReachable && !needsConnection) ? YES : NO;
}

- (AlicloudNetworkStatus)currentNetworkStatusForiOS7:(AlicloudNetworkStatus)status {
    NSString *nettype = networkInfo.currentRadioAccessTechnology;
    if (nettype)
    {
        if ([CTRadioAccessTechnologyGPRS isEqualToString:nettype] ||
            [CTRadioAccessTechnologyEdge isEqualToString:nettype] ||
            [CTRadioAccessTechnologyCDMA1x isEqualToString:nettype])
        {
            return AlicloudReachableVia2G;
        }
        else if ([CTRadioAccessTechnologyLTE isEqualToString:nettype])
        {
            return AlicloudReachableVia4G;
        }
        else if ([CTRadioAccessTechnologyWCDMA isEqualToString:nettype] ||
                 [CTRadioAccessTechnologyHSDPA isEqualToString:nettype] ||
                 [CTRadioAccessTechnologyHSUPA isEqualToString:nettype] ||
                 [CTRadioAccessTechnologyCDMAEVDORev0 isEqualToString:nettype] ||
                 [CTRadioAccessTechnologyCDMAEVDORevA isEqualToString:nettype] ||
                 [CTRadioAccessTechnologyCDMAEVDORevB isEqualToString:nettype] ||
                 [CTRadioAccessTechnologyeHRPD isEqualToString:nettype])
        {
            return AlicloudReachableVia3G;
        }

    }

    return status;
}

- (AlicloudNetworkStatus)_networkStatusForReachabilityFlags:(SCNetworkReachabilityFlags)flags {
    if ((flags & kSCNetworkReachabilityFlagsReachable) == 0 || ![self checkInternetConnection])
    {
        // The target host is not reachable.
        return AlicloudNotReachable;
    }

    AlicloudNetworkStatus returnValue = AlicloudNotReachable;

    if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0)
    {
        returnValue = AlicloudReachableViaWiFi;
    }

    if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) ||
         (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0))
    {
        if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0)
        {
            returnValue = AlicloudReachableViaWiFi;
        }
    }

    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN)
    {
        returnValue = AlicloudReachableVia4G;
    }

    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN)
    {
        if((flags & kSCNetworkReachabilityFlagsReachable) == kSCNetworkReachabilityFlagsReachable)
        {
            if ((flags & kSCNetworkReachabilityFlagsTransientConnection) == kSCNetworkReachabilityFlagsTransientConnection)
            {
                returnValue = AlicloudReachableVia3G;

                if((flags & kSCNetworkReachabilityFlagsConnectionRequired) == kSCNetworkReachabilityFlagsConnectionRequired)
                {
                    returnValue = AlicloudReachableVia2G;
                }
            }
        }
    }

    double version = [[UIDevice currentDevice].systemVersion doubleValue];
    if (version >= 7.0f && returnValue != AlicloudReachableViaWiFi)
    {
        returnValue = [self currentNetworkStatusForiOS7:returnValue];
    }

    return returnValue;
}

//网络变化回调函数
static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
    AlicloudNetworkStatus status = [[HttpdnsReachabilityManager shareInstance] _networkStatusForReachabilityFlags:flags];
    [[HttpdnsReachabilityManager shareInstance] updateCurStatus:status];

    if ([[HttpdnsIPv6Adapter sharedInstance] isIPv6OnlyNetwork]) {
        HttpdnsLogDebug("[AlicloudReachabilityManager]: Network changed, Pre network status is IPv6-Only.");
    } else {
        HttpdnsLogDebug("[AlicloudReachabilityManager]: Network changed, Pre network status is not IPv6-Only.");
    }

    [[HttpdnsIPv6Adapter sharedInstance] reResolveIPv6OnlyStatus];

    // network type change notify
    [[NSNotificationCenter defaultCenter] postNotificationName: ALICLOUD_NETWOEK_STATUS_NOTIFY
                                                        object: [[NSNumber alloc] initWithLong: (long)status]];
}

+ (BOOL)configureProxies {
    NSDictionary *proxySettings = CFBridgingRelease(CFNetworkCopySystemProxySettings());

    NSArray *proxies = nil;

    NSURL *url = [[NSURL alloc] initWithString:@"http://api.m.taobao.com"];

    proxies = CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)url,
                                                           (__bridge CFDictionaryRef)proxySettings));
    if (proxies > 0)
    {
        NSDictionary *settings = [proxies objectAtIndex:0];
        NSString* host = [settings objectForKey:(NSString *)kCFProxyHostNameKey];
        NSString* port = [settings objectForKey:(NSString *)kCFProxyPortNumberKey];

        if (host || port)
        {
            return YES;
        }
    }
    return NO;
}

- (void)dealloc {
    if (_reachabilityRef)
    {
        CFRelease(_reachabilityRef);
    }
}

@end
