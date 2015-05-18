//
//  HttpdnsModel.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    INITIALIZE,
    QUERYING,
    EXPIRED,
    VALID
} HostState;

@interface HttpdnsIpObject: NSObject<NSCopying>

@property (nonatomic, strong, getter=getIpString) NSString *ip;

@end



@interface HttpdnsHostObject : NSObject

@property (nonatomic, strong, setter=setHostName:, getter=getHostName) NSString *hostName;
@property (nonatomic, strong, setter=setIps:, getter=getIps) NSArray *ips;
@property (nonatomic, setter=setTTL:, getter=getTTL) long long ttl;
// 该域名的信息是在何时查询得到
@property (nonatomic, setter=setLastLookupTime:) long long lastLookupTime;
// 标记一个域名正处于什么状态(查询中、已过期、可用等)
@property (atomic, setter=setState:, getter=getState) HostState currentState;


-(instancetype)init;

// 根据查询时间和TTL判断该域名的信息是否已经过期
-(BOOL)isExpired;
@end



@interface FederationToken : NSObject

@property (nonatomic, strong) NSString *accessKeyId;
@property (nonatomic, strong) NSString *accessKeySecret;
@property (nonatomic, strong) NSString *securityToken;

@end