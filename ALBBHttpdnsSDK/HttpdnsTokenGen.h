//
//  HttpdnsTokenGen.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/26/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ALBBTDS/TDSService.h>
#import <ALBBTDS/TDSServiceProvider.h>
#import <ALBBTDS/FederationToken.h>
#import <ALBBTDS/TDSArgs.h>
#import <ALBBTDS/TDSLog.h>
#import <ALBBSDK/ALBBSDK.h>
#import <ALBBRpcSDK/ALBBRpcSDK.h>
#import "HttpdnsModel.h"
#import "HttpdnsLog.h"

@interface HttpdnsTokenGen : NSObject

@property(nonatomic, strong) id<TDSService> tds;
@property(nonatomic, strong) NSString *appId;

+(instancetype)sharedInstance;

-(HttpdnsToken *)getToken;
@end
