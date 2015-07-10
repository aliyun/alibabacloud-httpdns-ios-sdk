//
//  HttpdnsModel.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ALBBTDSSDK/TDSServiceProvider.h>
#import <ALBBTDSSDK/FederationToken.h>
#import <ALBBTDSSDK/TDSArgs.h>
#import <ALBBTDSSDK/TDSLog.h>
#import <ALBBSDK/ALBBSDK.h>
#import <ALBBRpcSDK/ALBBRpcSDK.h>
#import "HttpdnsLog.h"
#import "HttpdnsUtil.h"

@interface HttpdnsIpObject: NSObject<NSCoding> {
    NSString *ip;
}

@property (nonatomic, copy, getter=getIpString, setter=setIp:) NSString *ip;

@end


typedef NS_ENUM(NSInteger, HostState) {
    INITIALIZE,
    QUERYING,
    VALID
};



@interface HttpdnsHostObject : NSObject<NSCoding>

@property (nonatomic, strong, setter=setHostName:, getter=getHostName) NSString *hostName;
@property (nonatomic, strong, setter=setIps:, getter=getIps) NSArray *ips;
@property (nonatomic, setter=setTTL:, getter=getTTL) long long ttl;
@property (nonatomic, getter=getLastLookupTime, setter=setLastLookupTime:) long long lastLookupTime;
@property (atomic, setter=setState:, getter=getState) HostState currentState;

-(instancetype)init;

-(BOOL)isExpired;

-(BOOL)isAlreadyUnawailable;

-(NSString *)description;
@end



@interface HttpdnsToken : NSObject

@property (nonatomic, strong) NSString *accessKeyId;
@property (nonatomic, strong) NSString *accessKeySecret;
@property (nonatomic, strong) NSString *securityToken;
@property (nonatomic, strong) NSString *appId;

-(NSString *)description;
@end



@interface HttpdnsTokenGen : NSObject

@property(nonatomic, strong) id<TDSService> tds;
@property(nonatomic, strong) NSString *appId;

+(instancetype)sharedInstance;

-(HttpdnsToken *)getToken;

@end



@interface HttpdnsLocalCache : NSObject

+(void)writeToLocalCache:(NSDictionary *)allHostObjectInManagerDict;

+(NSDictionary *)readFromLocalCache;

+(void)cleanLocalCache;
@end