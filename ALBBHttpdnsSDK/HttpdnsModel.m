//
//  HttpdnsModel.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsModel.h"
#import "HttpdnsConfig.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"

#ifdef IS_DPA_RELEASE
#import <ALBBTDSSDK/TDSServiceProvider.h>
#import <ALBBTDSSDK/FederationToken.h>
#import <ALBBTDSSDK/TDSArgs.h>
#import <ALBBTDSSDK/TDSLog.h>
#import <ALBBSDK/ALBBSDK.h>
#import <ALBBRpcSDK/ALBBRpcSDK.h>
#endif

@implementation HttpdnsIpObject
@synthesize ip;

-(id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        ip = [aDecoder decodeObjectForKey:@"ip"];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:ip forKey:@"ip"];
}

-(NSString *)description {
    return ip;
}

@end

@implementation HttpdnsHostObject

-(instancetype)init {
    _hostName = nil;
    _currentState = INITIALIZE;
    _lastLookupTime = 0;
    _ttl = -1;
    _ips = nil;
    return self;
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _hostName = [aDecoder decodeObjectForKey:@"hostName"];
        _lastLookupTime = [aDecoder decodeInt64ForKey:@"lastLookupTime"];
        _ttl = [aDecoder decodeInt64ForKey:@"ttl"];
        _ips = [aDecoder decodeObjectForKey:@"ips"];
        _currentState = [aDecoder decodeIntegerForKey:@"currentState"];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_hostName forKey:@"hostName"];
    [aCoder encodeInt64:_lastLookupTime forKey:@"lastLookupTime"];
    [aCoder encodeInt64:_ttl forKey:@"ttl"];
    [aCoder encodeObject:_ips forKey:@"ips"];
    [aCoder encodeInteger:_currentState forKey:@"currentState"];
}

-(BOOL)isExpired {
    long long currentEpoch = (long long)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl < currentEpoch) {
        return YES;
    }
    return NO;
}

-(BOOL)isAlreadyUnawailable {
    long long currentEpoch = (long long)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl + MAX_EXPIRED_ENDURE_TIME_IN_SEC < currentEpoch) {
        return YES;
    }
    return NO;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"Host = %@ ips = %@ lastLookup = %lld ttl = %lld state = %ld",
            _hostName, _ips, _lastLookupTime, _ttl, (long)_currentState];
}

@end

@implementation HttpdnsToken : NSObject

-(NSString *)description {
    return [NSString stringWithFormat:@"Token: ak = %@ sk = %@ sToken = %@", _accessKeyId, _accessKeySecret, _securityToken];
}
@end


@implementation HttpdnsCustomSignerCredentialProvider

-(instancetype)initWithSignerBlock:(NSString *(^)(NSString *))signerBlock {
    if (self = [super init]) {
        self.signerBlock = signerBlock;
    }
    return self;
}

-(NSString *)sign:(NSString *)stringToSign {
    return self.signerBlock(stringToSign);
}

@end

#ifdef IS_DPA_RELEASE
@implementation HttpdnsTokenGen {
    id<TDSService> _tds;
}

+(instancetype)sharedInstance {
    static dispatch_once_t _pred = 0;
    __strong static HttpdnsTokenGen * _tokenGen = nil;
    dispatch_once(&_pred, ^{
        _tokenGen = [[self alloc] init];
    });
    return _tokenGen;
}

-(HttpdnsToken *)getToken {
    _tds = [TDSServiceProvider getService];
    FederationToken *token = [_tds distributeToken:HTTPDNS_TOKEN];
    if (token) {
        HttpdnsToken *httpDnsToken = [[HttpdnsToken alloc] init];
        [httpDnsToken setAccessKeyId:[token accessKeyId]];
        [httpDnsToken setAccessKeySecret:[token accessKeySecret]];
        [httpDnsToken setSecurityToken:[token securityToken]];
        [httpDnsToken setAppId:[_tds getAppid]];
        return httpDnsToken;
    }
    return nil;
}

@end
#endif



static NSString *localCacheKey = @"httpdns_hostManagerData";
static long long lastWroteToCacheTime = 0;
static long long minimalIntervalInSecond = 10;

@implementation HttpdnsLocalCache

+(void)writeToLocalCache:(NSDictionary *)allHostObjectInManagerDict {
    long long currentTime = [HttpdnsUtil currentEpochTimeInSecond];
    // 如果离上次写缓存时间小于阈值，放弃此次写入
    if (currentTime - lastWroteToCacheTime < minimalIntervalInSecond) {
        HttpdnsLogDebug(@"[writeToLocalCache] - Write too often, abort this writing");
        return;
    }
    lastWroteToCacheTime = currentTime;
    NSData *buffer = [NSKeyedArchiver archivedDataWithRootObject:allHostObjectInManagerDict];
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    [userDefault setObject:buffer forKey:localCacheKey];
    [userDefault synchronize];
    HttpdnsLogDebug(@"[writeToLocalCache] - write %lu to local file system", (unsigned long)(unsigned long)[allHostObjectInManagerDict count]);
}

+(NSDictionary *)readFromLocalCache {
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    NSData *buffer = [userDefault objectForKey:localCacheKey];
    NSDictionary *dict = [NSKeyedUnarchiver unarchiveObjectWithData:buffer];
    HttpdnsLogDebug(@"[readFromLocalCache] - read %lu from local file system: %@", (unsigned long)[dict count], dict);
    return dict;
}

+(void)cleanLocalCache {
    HttpdnsLogDebug(@"[cleanLocalCache] - clean cache");
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    [userDefault removeObjectForKey:localCacheKey];
}
@end