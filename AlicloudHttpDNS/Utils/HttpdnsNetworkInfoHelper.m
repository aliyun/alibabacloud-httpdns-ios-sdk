//
//  HttpdnsgetNetworkInfoHelper.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsNetworkInfoHelper.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import "HttpdnsLog_Internal.h"
#import "HttpdnsUtil.h"

static NSString *sNetworkStatusString = @"unknown";
static dispatch_queue_t sNetworkTypeQueue = 0;

@implementation HttpdnsNetworkInfoHelper

+ (void)initialize {
    sNetworkTypeQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.networkTypeQueue", DISPATCH_QUEUE_SERIAL);
}

+ (void)updateNetworkStatusString:(NSString *)statusString {
    dispatch_sync(sNetworkTypeQueue, ^{
        sNetworkStatusString = statusString;
    });
}

+ (NSString *)getNetworkType {
    __block NSString *networkType = nil;
    dispatch_sync(sNetworkTypeQueue, ^{
        networkType = sNetworkStatusString;
    });
    return networkType;
}

+ (BOOL)isWifiNetwork {
    __block BOOL res = NO;
    dispatch_sync(sNetworkTypeQueue, ^{
        res = ([sNetworkStatusString caseInsensitiveCompare:@"wifi"] == NSOrderedSame);
    });
    return res;
}

@end
