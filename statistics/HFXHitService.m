//
//  HFXHitService.m
//  hotfix-ios-sdk
//  HotFix埋点文档：http://gitlab.alibaba-inc.com/alicloud-ams/ams-doc/blob/master/SDK/ProductReport/hotfix.md
//  Created by junmo on 2017/9/27.
//  Copyright © 2017年 junmo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AlicloudUtils/AlicloudTrackerManager.h>
#import <AlicloudUtils/AlicloudTracker.h>
#import "HFXHitService.h"
#import "HFXStore.h"

static NSString *const TRACKER_ID = @"hotfix";
static NSString *const EVENT_BIZ_ACTIVE = @"biz_active";
static NSString *const EVENT_BIZ_DOWNLOAD_BEFORE = @"biz_download_before";
static NSString *const EVENT_BIZ_DOWNLOAD_SUCCESS = @"biz_download_success";
static NSString *const EVENT_BIZ_LOAD_PATCH = @"biz_load_patch";
static NSString *const EVENT_ERR_DOWNLOAD_FAIL = @"err_download_fail";
static NSString *const EVENT_ERR_INSTALL_FAIL = @"err_install_fail";
static NSString *const EVENT_PERF_PATCH_LOAD_TIME = @"perf_patch_load_time";

static NSString *const EVENT_PROPERTY_KEY_PATCH_VERSION = @"patchVersion";
static NSString *const EVENT_PROPERTY_KEY_PATCH_TYPE = @"patchType";
static NSString *const EVENT_PROPERTY_KEY_LOAD_TYPE = @"loadType";
static NSString *const EVENT_PROPERTY_KEY_PATCH_UUID = @"patchUuid";
static NSString *const EVENT_PROPERTY_KEY_ERR_CODE = @"errCode";
static NSString *const EVENT_PROPERTY_KEY_ERR_MSG = @"errMsg";
static NSString *const EVENT_PROPERTY_KEY_TIME_COST = @"cost";

static NSString *const DEFAULT_PATCH_TYPE_VALUE = @"lua";
static NSString *const DEFAULT_LOAD_TYPE_VALUE = @"iOS";

static AlicloudTracker *_tracker;
static BOOL _disableStatus = NO;

@implementation HFXHitService

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _tracker = [[AlicloudTrackerManager getInstance] getTrackerBySdkId:TRACKER_ID version:[[HFXStore sharedInstance] sdkVersion]];
    });
}

+ (void)setGlobalProperty {
    /* set global property */
    [_tracker setGlobalProperty:@"appKey" value:[HFXStore sharedInstance].appKey];
    /* 【注意】假设用户手动设置appVersion，本方法需要重新调用 */
    [_tracker setGlobalProperty:@"appVersion" value:[[HFXStore sharedInstance] userAppVersion]];
}

+ (void)disableHitService {
    _disableStatus = YES;
}

+ (void)bizActiveHit {
    if (_disableStatus) {
        return;
    }
    [_tracker sendCustomHit:EVENT_BIZ_ACTIVE duration:0 properties:nil];
}

+ (void)bizDownloadBeforeHit:(NSString *)patchVersion {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:patchVersion forKey:EVENT_PROPERTY_KEY_PATCH_VERSION];
        [extProperties setObject:DEFAULT_PATCH_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_PATCH_TYPE];
        [extProperties setObject:DEFAULT_LOAD_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_LOAD_TYPE];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:EVENT_BIZ_DOWNLOAD_BEFORE duration:0 properties:extProperties];
}

+ (void)bizDownloadSuccessHit:(NSString *)patchVersion {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:patchVersion forKey:EVENT_PROPERTY_KEY_PATCH_VERSION];
        [extProperties setObject:DEFAULT_PATCH_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_PATCH_TYPE];
        [extProperties setObject:DEFAULT_LOAD_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_LOAD_TYPE];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:EVENT_BIZ_DOWNLOAD_SUCCESS duration:0 properties:extProperties];
}

+ (void)bizLoadPatchHit:(NSString *)patchVersion {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:patchVersion forKey:EVENT_PROPERTY_KEY_PATCH_VERSION];
        [extProperties setObject:DEFAULT_PATCH_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_PATCH_TYPE];
        [extProperties setObject:DEFAULT_LOAD_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_LOAD_TYPE];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:EVENT_BIZ_LOAD_PATCH duration:0 properties:extProperties];
}

+ (void)errDownloadFailHit:(NSString *)patchVersion
                 patchUuid:(NSString *)patchUuid
                 errorCode:(NSString *)errCode
              errorMessage:(NSString *)errMsg {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:patchVersion forKey:EVENT_PROPERTY_KEY_PATCH_VERSION];
        [extProperties setObject:DEFAULT_PATCH_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_PATCH_TYPE];
        [extProperties setObject:DEFAULT_LOAD_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_LOAD_TYPE];
        [extProperties setObject:patchUuid forKey:EVENT_PROPERTY_KEY_PATCH_UUID];
        [extProperties setObject:errCode forKey:EVENT_PROPERTY_KEY_ERR_CODE];
        [extProperties setObject:errMsg forKey:EVENT_PROPERTY_KEY_ERR_MSG];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:EVENT_ERR_DOWNLOAD_FAIL duration:0 properties:extProperties];
}

+ (void)errInstallFailHit:(NSString *)patchVersion
                patchUuid:(NSString *)patchUuid
                errorCode:(NSString *)errCode
             errorMessage:(NSString *)errMsg {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:patchVersion forKey:EVENT_PROPERTY_KEY_PATCH_VERSION];
        [extProperties setObject:DEFAULT_PATCH_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_PATCH_TYPE];
        [extProperties setObject:DEFAULT_LOAD_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_LOAD_TYPE];
        [extProperties setObject:patchUuid forKey:EVENT_PROPERTY_KEY_PATCH_UUID];
        [extProperties setObject:errCode forKey:EVENT_PROPERTY_KEY_ERR_CODE];
        [extProperties setObject:errMsg forKey:EVENT_PROPERTY_KEY_ERR_MSG];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:EVENT_ERR_INSTALL_FAIL duration:0 properties:extProperties];
}

+ (void)perfPatchLoadTimeHit:(NSString *)patchVersion
                   patchUuid:(NSString *)patchUuid
                        cost:(long long)timeCost {
    if (_disableStatus) {
        return;
    }
    NSMutableDictionary *extProperties = [NSMutableDictionary dictionary];
    @try {
        [extProperties setObject:patchVersion forKey:EVENT_PROPERTY_KEY_PATCH_VERSION];
        [extProperties setObject:DEFAULT_PATCH_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_PATCH_TYPE];
        [extProperties setObject:DEFAULT_LOAD_TYPE_VALUE forKey:EVENT_PROPERTY_KEY_LOAD_TYPE];
        [extProperties setObject:patchUuid forKey:EVENT_PROPERTY_KEY_PATCH_UUID];
        [extProperties setObject:[NSNumber numberWithLongLong:timeCost] forKey:EVENT_PROPERTY_KEY_TIME_COST];
    } @catch (NSException *e) {}
    [_tracker sendCustomHit:EVENT_PERF_PATCH_LOAD_TIME duration:0 properties:extProperties];
}

@end
