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

static NSUInteger const ALICLOUD_HTTPDNS_CARRIER_CHINA_CODE = 460;
#define ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(type) [NSString stringWithFormat:@"%@", @(type)]

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
        if (currentWifiHotSpotName.length == 0 || !currentWifiHotSpotName) {
            HttpdnsLogDebug("Get wifi name failed!");
            return nil;
        }
        //加前缀“4-”防止，wifi名字是0-3的数字，导致缓存时与运营商信息混淆。
        NSString *networkName = [NSString stringWithFormat:@"%@-%@", ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeWifi), currentWifiHotSpotName];
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

+ (NSString *)checkMobileOperator {
    CTTelephonyNetworkInfo *info = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = info.subscriberCellularProvider;
    NSString *carrierName = carrier.carrierName;// 运营商名称
    NSString *mobileCountryCode = carrier.mobileCountryCode;// 运营商国家编号
    NSString *mobileNetworkCode = carrier.mobileNetworkCode;// 运营商编号
    if (!mobileNetworkCode) {
        return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeUnknown);//查询不到运营商
    }
    if ([mobileCountryCode intValue] == ALICLOUD_HTTPDNS_CARRIER_CHINA_CODE) { // 中国
        if ([carrierName rangeOfString:@"联通"].length>0 || [mobileNetworkCode isEqualToString:@"01"] || [mobileNetworkCode isEqualToString:@"06"]) {
            return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeChinaUnicom);//中国联通
        } else if ([carrierName rangeOfString:@"移动"].length>0 || [mobileNetworkCode isEqualToString:@"00"] || [mobileNetworkCode isEqualToString:@"02"] || [mobileNetworkCode isEqualToString:@"07"]) {
            return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeChinaMobile);//中国移动
        } else if ([carrierName rangeOfString:@"电信"].length>0 || [mobileNetworkCode isEqualToString:@"03"] || [mobileNetworkCode isEqualToString:@"05"]) {
            return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeChinaTelecom);//中国电信
        }
        //        else if ([carrierName rangeOfString:@"铁通"].length>0 || [mobileNetworkCode isEqualToString:@"20"]) {
        //            return @"中国铁通";
        //        }
    }
    return [self statusBarCheckMobileOperator];
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
        if ([carrierName rangeOfString:@"联通"].length>0) {
            return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeChinaUnicom);//中国联通
        } else if ([carrierName rangeOfString:@"移动"].length>0) {
            return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeChinaMobile);//中国移动
        } else if ([carrierName rangeOfString:@"电信"].length>0) {
            return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeChinaTelecom);//中国电信
        }
        //        else if ([carrierName rangeOfString:@"铁通"].length>0) {
        //            return @"中国铁通";
        //        }
        return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeUnknown);//查询不到运营商
    }
    return ALICLOUD_HTTPDNS_NETWORK_FROME_TYPE(HttpdnsCarrierTypeUnknown);//查询不到运营商
}

@end
