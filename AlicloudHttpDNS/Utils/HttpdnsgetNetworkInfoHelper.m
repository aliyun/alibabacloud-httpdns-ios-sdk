//
//  HttpdnsgetNetworkInfoHelper.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsgetNetworkInfoHelper.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import "HttpdnsLog.h"
#import "HttpdnsUtil.h"

typedef NS_ENUM(NSInteger, HttpdnsCarrierType) {
    HttpdnsCarrierTypeUnknown,/**< 未知运营商 */
    HttpdnsCarrierTypeWWAN,   /**< 移动运营商 */
    HttpdnsCarrierTypeWifi    /**< Wifi */
};

static NSString *sNetworkType = @"unknown";
static NSString *sWifiBssid = @"unknown";

@implementation HttpdnsgetNetworkInfoHelper

#define ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(type) [NSString stringWithFormat:@"%@", @(type)]
#define ALICLOUD_HTTPDNS_NETWORK_FROME_COUNTRY_NETWORK(type, mobileCountryCode, mobileNetworkCode) [NSString stringWithFormat:@"%@-%@-%@", @(type), mobileCountryCode, mobileNetworkCode]
#define ALICLOUD_HTTPDNS_NETWORK_FROME_WIFI_SSID(type, SSID) [NSString stringWithFormat:@"%@-%@", @(type), SSID]

/**
 *  获取运营商名称
 */
+ (NSString *)getCarrierName {
    CTTelephonyNetworkInfo *NetworkInfo = [[CTTelephonyNetworkInfo alloc]init];
    return  [[NetworkInfo subscriberCellularProvider] carrierName];
}

+ (NSString *)getNetworkName {
    if ([HttpdnsUtil isWifiEnable]) {
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
    if ([HttpdnsUtil isCarrierConnectEnable]) {
        NSString *networkName = [self checkMobileOperator];
        return networkName;
    }
    
    HttpdnsLogDebug("Get network name failed!");
    return nil;
}

+ (NSString *)getCurrentWifiHotSpotName {
    NSString *wifiName = nil;
    NSArray *ifs = (__bridge_transfer id)CNCopySupportedInterfaces();
    for (NSString *ifnam in ifs) {
        NSDictionary *info = (__bridge_transfer id)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
        @try {
            if (info[@"SSID"]) {
                wifiName = info[@"SSID"];
            }
        } @catch (NSException *exception) {}
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
    if (mobileCountryCode && mobileCountryCode.length > 0 && mobileNetworkCode && mobileNetworkCode.length > 0) {
        return ALICLOUD_HTTPDNS_NETWORK_FROME_COUNTRY_NETWORK(HttpdnsCarrierTypeWWAN, mobileCountryCode, mobileNetworkCode);
    }
    return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeUnknown);//查询不到运营商
}

+ (void)updateNetworkStatus:(AlicloudNetworkStatus)status {
    @synchronized(self) {
        switch (status) {
            case AlicloudReachableViaWiFi:
                sNetworkType = @"wifi";
                [self updateWifiBssid];
                break;
            case AlicloudReachableVia2G:
                sNetworkType = @"2g";
                break;
            case AlicloudReachableVia3G:
                sNetworkType = @"3g";
                break;
            case AlicloudReachableVia4G:
                sNetworkType = @"4g";
                break;
            case AlicloudNotReachable:
                sNetworkType = @"unknown";
                break;
            default:
                sNetworkType = @"unknown";
                break;
        }
        HttpdnsLogDebug(@"Update network status: %d, network type: %@", status, sNetworkType);
    }
}

+ (NSString *)getNetworkType {
    return sNetworkType;
}

+ (BOOL)isWifiNetwork {
    return [sNetworkType isEqualToString:@"wifi"];
}

+ (void)updateWifiBssid {
    NSString *wifiBssid = nil;
    NSArray *ifs = (id)CFBridgingRelease(CNCopySupportedInterfaces());
    for (NSString *ifnam in ifs) {
        id info = (id)CFBridgingRelease(CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam));
        wifiBssid = [info objectForKey:(NSString*)kCNNetworkInfoKeyBSSID];
        if (wifiBssid.length <= 0) {
            continue;
        }
    }
    
    if ([HttpdnsUtil isValidString:wifiBssid]) {
        sWifiBssid = wifiBssid;
    }
}

+ (NSString *)getWifiBssid {
    return sWifiBssid;
}

@end
