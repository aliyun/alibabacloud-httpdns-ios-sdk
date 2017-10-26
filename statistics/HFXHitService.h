//
//  HFXHitService.h
//  AlicloudHotFix
//
//  Created by junmo on 2017/9/27.
//  Copyright © 2017年 junmo. All rights reserved.
//

#ifndef HFXHitService_h
#define HFXHitService_h

@interface HFXHitService : NSObject

+ (void)setGlobalProperty;
+ (void)disableHitService;

+ (void)bizActiveHit;

+ (void)bizDownloadBeforeHit:(NSString *)patchVersion;

+ (void)bizDownloadSuccessHit:(NSString *)patchVersion;

+ (void)bizLoadPatchHit:(NSString *)patchVersion;

+ (void)errDownloadFailHit:(NSString *)patchVersion
                 patchUuid:(NSString *)patchUuid
                 errorCode:(NSString *)errCode
              errorMessage:(NSString *)errMsg;

+ (void)errInstallFailHit:(NSString *)patchVersion
                patchUuid:(NSString *)patchUuid
                errorCode:(NSString *)errCode
             errorMessage:(NSString *)errMsg;

+ (void)perfPatchLoadTimeHit:(NSString *)patchVersion
                   patchUuid:(NSString *)patchUuid
                        cost:(long long)timeCost;

@end

#endif /* HFXHitService_h */
