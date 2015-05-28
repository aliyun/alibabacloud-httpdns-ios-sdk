//
//  HttpdnsTokenGen.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/26/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsTokenGen.h"

@implementation HttpdnsTokenGen

+(instancetype)sharedInstance {
    static dispatch_once_t _pred = 0;
    __strong static HttpdnsTokenGen * _tokenGen = nil;
    dispatch_once(&_pred, ^{
        _tokenGen = [[self alloc] init];
    });
    return _tokenGen;
}

-(void)setUpEnvironment {
    [[ALBBSDK sharedInstance] setALBBSDKEnvironment:ALBBSDKEnvironmentDaily];
    [ALBBRpcSDK setEnvironment:ALBBRpcSDKEnvironmentDaily];
    [[ALBBSDK sharedInstance] asyncInit:^{
        HttpdnsLogDebug(@"init success!");
        [TDSLog enableLog:YES];
        _tds = [TDSServiceProvider getService];
        [_tds distributeToken:HTTPDNS_TOKEN];

        OpenSecurityGuardManager *osgMgr = [OpenSecurityGuardManager getInstance];
        if (osgMgr) {
            id<IOpenStaticDataStoreComponent> component = [osgMgr getStaticDataStoreComp];
            if (component) {
                NSString *extraData = [component getExtraData: @"appId" authCode: @""];
                if (extraData) {
                    _appId = extraData;
                    HttpdnsLogDebug(@"[setUpEnviroment] - APPID:%@", extraData);
                } else {
                    HttpdnsLogError(@"[setUpEnviroment] - Can not get APPID from SecurityGuardManager.");
                }
            }
        }
    } failedCallback:^(NSError *error) {
        HttpdnsLogDebug(@"init failed! info: %@", error);
    }];
}

-(HttpdnsToken *)getToken {
    _tds = [TDSServiceProvider getService];
    FederationToken *token = [_tds distributeToken:HTTPDNS_TOKEN];
    if (token) {
        HttpdnsToken *httpDnsToken = [[HttpdnsToken alloc] init];
        [httpDnsToken setAccessKeyId:[token accessKeyId]];
        [httpDnsToken setAccessKeySecret:[token accessKeySecret]];
        [httpDnsToken setSecurityToken:[token securityToken]];
        return httpDnsToken;
    }
    return nil;
}
@end
