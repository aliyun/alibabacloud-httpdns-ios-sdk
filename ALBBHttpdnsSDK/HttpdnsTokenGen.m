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
    [[ALBBSDK sharedInstance] setALBBSDKEnvironment:ALBBSDKEnvironmentRelease];
    [ALBBRpcSDK setEnvironment:ALBBRpcSDKEnvironmentRelease];
    [[ALBBSDK sharedInstance] asyncInit:^{
        HttpdnsLogDebug(@"init success!");
        [TDSLog enableLog:YES];
        _tds = [TDSServiceProvider getService];
        [_tds initWithAppid:@"2078322"];
        [_tds distributeToken:HTTPDNS_TOKEN];

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
