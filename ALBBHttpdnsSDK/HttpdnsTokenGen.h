//
//  HttpdnsTokenGen.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/26/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TDS_IOS_SDK/TDSService.h>
#import <TDS_IOS_SDK/TDSServiceProvider.h>
#import <TDS_IOS_SDK/FederationToken.h>
#import <TDS_IOS_SDK/TDSArgs.h>
#import <TDS_IOS_SDK/TDSLog.h>
#import <ALBBRpcSDK/ALBBRpcSDK.h>
#import <ALBBSDK/ALBBSDK.h>
#import "HttpdnsModel.h"
#import "HttpdnsLog.h"
#import <SecurityGuardSDK/Open/OpenStaticDataStore/IOpenStaticDataStoreComponent.h>
#import <SecurityGuardSDK/Open/OpenSecurityGuardManager.h>

@interface HttpdnsTokenGen : NSObject

@property(nonatomic, strong) id<TDSService> tds;
@property(nonatomic, strong) NSString *appId;

+(instancetype)sharedInstance;
-(void)setUpEnvironment;
-(HttpdnsToken *)getToken;
@end
