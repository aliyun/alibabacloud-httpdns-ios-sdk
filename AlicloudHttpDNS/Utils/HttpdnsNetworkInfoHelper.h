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
#import "HttpdnsReachability.h"

@interface HttpdnsNetworkInfoHelper : NSObject

+ (void)updateNetworkStatusString:(NSString *)statusString;

+ (NSString *)getNetworkType;

+ (BOOL)isWifiNetwork;

@end
