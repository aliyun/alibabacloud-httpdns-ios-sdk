//
//  UIApplication+CYLExtension.h
//  AlicloudUtils
//
//  Created by 地风（ElonChan） on 16/5/16.
//  Copyright © 2016年 Ali. All rights reserved.
//

#import <UIKit/UIKit.h>

FOUNDATION_EXTERN NSString *const ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTEXT;
FOUNDATION_EXTERN NSUInteger const ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTINUOUS_CRASH_ON_LAUNCH_NEED_TO_FIX;

@interface UIApplication (ABSHTTPDNSSetting)

/*
 * 连续闪退检测前需要执行的逻辑，如上报统计初始化
 */
- (void)onBeforeBootingProtection;


@end
