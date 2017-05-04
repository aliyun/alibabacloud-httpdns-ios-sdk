//
//  HttpdnsgetNetworkInfoHelper.m
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsgetNetworkInfoHelper.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import "HttpdnsLog.h"

@implementation HttpdnsgetNetworkInfoHelper

#define ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(type) [NSString stringWithFormat:@"%@", @(type)]
#define ALICLOUD_HTTPDNS_NETWORK_FROME_COUNTRY_NETWORK(type, mobileCountryCode, mobileNetworkCode) [NSString stringWithFormat:@"%@-%@-%@", @(type), mobileCountryCode, mobileNetworkCode]

#define ALICLOUD_HTTPDNS_NETWORK_FROME_WIFI_SSID(type, SSID) [NSString stringWithFormat:@"%@-%@", @(type), SSID]

//wifi是否可用
+ (BOOL)isWifiEnable {
    return ([[AVReachability reachabilityForLocalWiFi] currentReachabilityStatus] == AVReachableViaWiFi);
}

//蜂窝移动网络是否可用
+ (BOOL)isCarrierConnectEnable {
    return ([[AVReachability reachabilityForInternetConnection] currentReachabilityStatus] == AVReachableViaWWAN);
}

/**
 *  获取运营商名称
 */
+ (NSString *)getCarrierName {
    CTTelephonyNetworkInfo *NetworkInfo = [[CTTelephonyNetworkInfo alloc]init];
    return  [[NetworkInfo subscriberCellularProvider] carrierName];
}

+ (NSString *)getNetworkName {
    if (self.isWifiEnable) {
        NSString *currentWifiHotSpotName = [self getCurrentWifiHotSpotName];
        NSString *networkName = ALICLOUD_HTTPDNS_NETWORK_FROME_WIFI_SSID(HttpdnsCarrierTypeWifi, @"0");
        if (currentWifiHotSpotName.length == 0 || !currentWifiHotSpotName) {
            HttpdnsLogDebug("Get wifi name failed!");
            //若读不到WIFI名字，则默认为2-0
            return networkName;
        }
        //加前缀“2-”防止，wifi名字是0-3的数字，导致缓存时与运营商信息混淆。
        networkName = ALICLOUD_HTTPDNS_NETWORK_FROME_WIFI_SSID(HttpdnsCarrierTypeWifi, currentWifiHotSpotName);
        return networkName;
    }
    if (self.isCarrierConnectEnable) {
        return [self checkMobileOperator];
    }
    HttpdnsLogDebug("Get network name failed!");
    return nil;
}

+ (NSString *)getCurrentWifiHotSpotName {
    NSString *wifiName = nil;
    NSArray *ifs = (__bridge_transfer id)CNCopySupportedInterfaces();
    for (NSString *ifnam in ifs) {
        NSDictionary *info = (__bridge_transfer id)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
        if (info[@"SSID"]) {
            wifiName = info[@"SSID"];
        }
    }
    return wifiName;
}
/*!
 * 
 联通     1-460-01
         1-460-06
 移动     1-460-00
         1-460-02
         1-460-07
 电信     1-460-03
         1-460-05
 */
+ (NSString *)checkMobileOperator {
    CTTelephonyNetworkInfo *info = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = info.subscriberCellularProvider;
    NSString *mobileCountryCode = carrier.mobileCountryCode;// 运营商国家编号
    NSString *mobileNetworkCode = carrier.mobileNetworkCode;// 运营商编号
    //没有装SIM卡
    if (!carrier.isoCountryCode) {
        return [self statusBarCheckMobileOperator];
    }
    //装了SIM卡
    if (mobileCountryCode && mobileCountryCode.length > 0 && mobileNetworkCode && mobileNetworkCode.length > 0) {
        return ALICLOUD_HTTPDNS_NETWORK_FROME_COUNTRY_NETWORK(HttpdnsCarrierTypeWWAN, mobileCountryCode, mobileNetworkCode);
    }
    return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeUnknown);//查询不到运营商
}

/**
 *  对于美版或者日版卡贴iPhone，检测到的CTCarrier并非sim卡信息，此时就需要通过StatusBar实时检测当前网络运行商
 */
+ (NSString *)statusBarCheckMobileOperator {
    NSArray *subviews = [[[[UIApplication sharedApplication] valueForKey:@"statusBar"] valueForKey:@"foregroundView"] subviews];
    UIView *serviceView = nil;
    Class serviceClass = NSClassFromString([NSString stringWithFormat:@"UIStat%@Serv%@%@", @"usBar", @"ice", @"ItemView"]);
    for (UIView *subview in subviews) {
        if([subview isKindOfClass:[serviceClass class]]) {
            serviceView = subview;
            break;
        }
    }
    if (serviceView) {
        NSString *carrierName = [serviceView valueForKey:[@"service" stringByAppendingString:@"String"]];
        if (carrierName && carrierName.length > 0) {
            return carrierName;
        }
    }
    return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeUnknown);//查询不到运营商
}

@end
