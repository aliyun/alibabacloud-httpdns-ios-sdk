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

NSString *const ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTEXT = @"ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTEXT";
NSUInteger const ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTINUOUS_CRASH_ON_LAUNCH_NEED_TO_FIX = 2;
static NSUInteger const ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTINUOUS_CRASH_ON_LAUNCH_NEED_TO_REPORT = 2;
static NSTimeInterval const ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CRASH_ON_LAUNCH_TIMEINTERVAL_THRESHOLD = 15.0;

@implementation UIApplication (ABSHTTPDNSSetting)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self abs_swizzleSetDelegate];
    });
}

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
    ABSBootingProtection *bootingProtection = [[ABSBootingProtection alloc]
                                               initWithContinuousCrashOnLaunchNeedToReport:ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTINUOUS_CRASH_ON_LAUNCH_NEED_TO_REPORT
                                                                                     continuousCrashOnLaunchNeedToFix:ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTINUOUS_CRASH_ON_LAUNCH_NEED_TO_FIX
                                                                                   crashOnLaunchTimeIntervalThreshold:ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CRASH_ON_LAUNCH_TIMEINTERVAL_THRESHOLD
                                                                                                                context:ALICLOUD_HTTPDNS_BOOTING_PROTECTION_CONTEXT
                                              ];
    [bootingProtection setRepairBlock:^(ABSBoolCompletionHandler completionHandler) {
        NSString *log = [NSString stringWithFormat:@"booting protection"];
        [HttpDnsHitService bizContinuousBootingCrashWithLog:log];
        [self onBootingProtectionWithCompletion:completionHandler];
    }];
    
    [ABSUtil setLogger:^(NSString *msg) {
        // 设置Logger
        HttpdnsLogDebug("Alibaba ABS : %@", msg);
    }];
    [bootingProtection launchContinuousCrashProtect];
}

/*
 * 修复逻辑：删除文件
 */
- (BOOL)onBootingProtectionSync {
   return [HttpdnsPersistenceUtils deleteAllCacheFiles];
}

- (void)deleteAllCacheFilesSync:(ABSBoolCompletionHandler)completion {
    @autoreleasepool {
        // 删除缓存文件
        BOOL success = [self onBootingProtectionSync];
        NSInteger code = 0;
        NSString *errorReasonText = @"Booting Protection Operation failed";
        NSDictionary *errorInfo = @{
                                    @"code" : @(code),
                                      NSLocalizedDescriptionKey : errorReasonText,
                                      };
        NSError *error = [NSError errorWithDomain:NSStringFromClass([self class])
                                             code:code
                                         userInfo:errorInfo];
        //在所有操作都结束时调用
        if (completion) completion(success, success ? nil : error);
    }
}

#pragma mark - 修复启动连续 Crash 逻辑
- (void)onBootingProtectionWithCompletion:(ABSBoolCompletionHandler)completion {
    NSThread *onBootingProtectionAsyncThread = [[NSThread alloc] initWithTarget:self selector:@selector(deleteAllCacheFilesSync:) object:completion];
    [onBootingProtectionAsyncThread start];
}

@end
