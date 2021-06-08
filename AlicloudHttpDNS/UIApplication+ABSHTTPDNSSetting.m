//
//  UIApplication+CYLExtension.m
//  AlicloudUtils
//
//  Created by 地风（ElonChan） on 16/5/16.
//  Copyright © 2016年 Ali. All rights reserved.
//

#import "UIApplication+ABSHTTPDNSSetting.h"
#import <objc/runtime.h>
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsLog.h"
#import "HttpDnsHitService.h"
#import "HttpdnsConstants.h"
#import "AlicloudHttpDNS.h"

NSString *const ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTEXT = @"ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTEXT";
NSUInteger const ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTINUOUS_CRASH_ON_LAUNCH_NEED_TO_FIX = 2;

@implementation UIApplication (ABSHTTPDNSSetting)

//+ (void)load {
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        [self abs_swizzleSetDelegate];
//    });
//}

+ (void)abs_swizzleSetDelegate {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        abs_httpdns_classMethodSwizzle([self class], @selector(setDelegate:), @selector(abs_setDelegate:));
    });
}

- (void)abs_setDelegate:(id<UIApplicationDelegate>)delegate {
    [self abs_setDelegate:delegate];
    /* ------- 启动连续闪退保护 ------- */
    [self onBeforeBootingProtection];
}

#pragma mark - private method

BOOL abs_httpdns_classMethodSwizzle(Class aClass, SEL originalSelector, SEL swizzleSelector) {
    Method originalMethod = class_getInstanceMethod(aClass, originalSelector);
    Method swizzleMethod = class_getInstanceMethod(aClass, swizzleSelector);
    BOOL didAddMethod =
    class_addMethod(aClass,
                    originalSelector,
                    method_getImplementation(swizzleMethod),
                    method_getTypeEncoding(swizzleMethod));
    if (didAddMethod) {
        class_replaceMethod(aClass,
                            swizzleSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzleMethod);
    }
    return YES;
}

/*
 * 连续闪退检测前需要执行的逻辑，如上报统计初始化
 */
- (void)onBeforeBootingProtection {
    [[EMASSecurityModeManager sharedInstance] registerSDKComponentAndStartCheck:@"httpdns"
                                                                     sdkVersion:HTTPDNS_IOS_SDK_VERSION
                                                                         appKey:HTTPDNS_BEACON_APPKEY
                                                                      appSecret:HTTPDNS_BEACON_APPSECRECT
                                                              sdkCrashThreshold:ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTINUOUS_CRASH_ON_LAUNCH_NEED_TO_FIX
                                                                      onSuccess:^{
                                                                          //成功情况暂不处理
                                                                      } onCrash:^(NSUInteger crashCount) {
                                                                          if (crashCount >= ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTINUOUS_CRASH_ON_LAUNCH_NEED_TO_FIX ) {
                                                                              NSString *log = [NSString stringWithFormat:@"booting protection"];
                                                                              [HttpDnsHitService bizContinuousBootingCrashWithLog:log];
                                                                              [HttpdnsPersistenceUtils deleteAllCacheFiles];
                                                                          }
                                                                      }];
}

@end
