//
//  HttpdnsgetNetworkInfoHelper.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import "AVReachability.h"

typedef NS_ENUM(NSInteger, HttpdnsCarrierType) {
    HttpdnsCarrierTypeUnknown,/**< 未知运营商 */
    HttpdnsCarrierTypeWWAN,   /**< 移动运营商 */
    HttpdnsCarrierTypeWifi    /**< Wifi */
};

@interface HttpdnsgetNetworkInfoHelper : NSObject

/*!
 * 当前网络运营商名字，或者wifi名字
 */
+ (NSString *)getNetworkName;

@end
