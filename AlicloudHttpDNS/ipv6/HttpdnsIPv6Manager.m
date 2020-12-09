//
//  HttpdnsIPv6Manager.m
//  AlicloudHttpDNS
//
//  Created by junmo on 2018/8/31.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import <AlicloudUtils/AlicloudIPv6Adapter.h>
#import <AlicloudUtils/EMASTools.h>
#import "HttpdnsIPv6Manager.h"
#import "HttpDnsHitService.h"
#import "HttpdnsUtil.h"



static NSString *const QueryCacheIPV4 = @"QueryCacheIPV4";
static NSString *const QueryCacheIPV6 = @"QueryCacheIPV6";

@interface HttpdnsIPv6Manager()

@property (nonatomic, assign) BOOL usersetIPv6ResultEnable;

/// 存储域名查询ip类型 ipv4 || ipv6
@property (nonatomic, strong) NSMutableDictionary <NSString *,NSArray <NSString *>*>*ipQueryCache;


@end

@implementation HttpdnsIPv6Manager

- (instancetype)init {
    if (self = [super init]) {
        _usersetIPv6ResultEnable = NO;
        self.ipQueryCache = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (instancetype)sharedInstance {
    static id singletonInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!singletonInstance) {
            singletonInstance = [[super allocWithZone:NULL] init];
        }
    });
    return singletonInstance;
}

+ (id)allocWithZone:(struct _NSZone *)zone {
    return [self sharedInstance];
}

- (id)copyWithZone:(struct _NSZone *)zone {
    return self;
}

- (void)setIPv6ResultEnable:(BOOL)enable {
    _usersetIPv6ResultEnable = enable;
    [HttpDnsHitService bizIPv6Enable:enable];
}

- (NSString *)assembleIPv6ResultURL:(NSString *)originURL queryHost:(NSString *)queryHost {
    if (![EMASTools isValidString:originURL]) {
        return originURL;
    }
    
    NSArray *cacheArr = [HttpdnsUtil safeObjectForKey:queryHost dict:self.ipQueryCache];
    if ([EMASTools isValidArray:cacheArr]) {
        if (cacheArr.count == 2) {
            originURL = [NSString stringWithFormat:@"%@&query=%@", originURL, [EMASTools URLEncodedString:@"4,6"]];
        } else {
            if ([cacheArr containsObject:QueryCacheIPV6]) {
                originURL = [NSString stringWithFormat:@"%@&query=%@", originURL, [EMASTools URLEncodedString:@"6"]];
            }
        }
    }
    
    //删除当前域名的查询策略
    [self removeQueryHost:queryHost];
    return originURL;
}

- (BOOL)isAbleToResolveIPv6Result {
    return _usersetIPv6ResultEnable;
}


- (void)setQueryHost:(NSString *)host ipQueryType:(HttpdnsIPType)queryType{
    @synchronized (self) {
        
        if ([EMASTools isValidString:host]) {
            NSArray *cacheArr = [HttpdnsUtil safeObjectForKey:host dict:self.ipQueryCache];
            
            if (cacheArr.count == 2) {
                return;
            }
            
            if (![EMASTools isValidArray:cacheArr]) {  //当前缓存中无当前域名查询策略
                NSMutableArray *cacheMArr = [NSMutableArray array];
                if (queryType & HttpdnsIPTypeIpv4) {  //ipv4 查询
                    [cacheMArr addObject:QueryCacheIPV4];
                }
                
                if (queryType & HttpdnsIPTypeIpv6) {  //ipv6 查询
                    [cacheMArr addObject:QueryCacheIPV6];
                }
                [HttpdnsUtil safeAddValue:cacheMArr key:host toDict:self.ipQueryCache];
                
            } else {  //当前缓存中存在该域名的查询策略
                
                NSMutableArray *cacheMArr = [NSMutableArray arrayWithArray:cacheArr];
                if ([cacheArr containsObject:QueryCacheIPV4]) {
                    if (queryType & HttpdnsIPTypeIpv6) {
                        [cacheMArr addObject:QueryCacheIPV6];
                    }
                } else {
                    if (queryType & HttpdnsIPTypeIpv4) {
                        [cacheMArr addObject:QueryCacheIPV4];
                    }
                }
                [HttpdnsUtil safeAddValue:cacheMArr key:host toDict:self.ipQueryCache];
                
            }
        }
        
    }
}


- (void)removeQueryHost:(NSString *)host {
    @synchronized (self) {
        [self.ipQueryCache removeObjectForKey:host];
    }
}

@end
