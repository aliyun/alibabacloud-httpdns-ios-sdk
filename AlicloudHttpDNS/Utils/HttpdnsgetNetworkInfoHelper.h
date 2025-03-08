//
//  HttpdnsgetNetworkInfoHelper.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import "HttpdnsReachabilityManager.h"

@interface HttpdnsgetNetworkInfoHelper : NSObject

/*!
 * 当前网络运营商名字，或者wifi名字
 */
+ (NSString *)getNetworkName;

+ (void)updateNetworkStatus:(AlicloudNetworkStatus)status;
+ (NSString *)getNetworkType;
+ (BOOL)isWifiNetwork;
+ (NSString *)getWifiBssid;


/// 设置networkInfo 开关 默认打开
+ (void)setNetworkInfoEnable:(BOOL)enable;


@end
