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



static NSString *const QueryCacheIPV4Key = @"QueryCacheIPV4Key";
static NSString *const QueryCacheIPV6Key = @"QueryCacheIPV6Key";

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
            if ([cacheArr containsObject:QueryCacheIPV6Key]) {
                originURL = [NSString stringWithFormat:@"%@&query=%@", originURL, @"6"];
            }
        }
    }
    
    return originURL;
}

- (BOOL)isAbleToResolveIPv6Result {
    return _usersetIPv6ResultEnable;
}


- (void)setQueryHost:(NSString *)host ipQueryType:(HttpdnsQueryIPType)queryType{
    @synchronized (self) {
        
        if ([EMASTools isValidString:host]) {
            NSArray *cacheArr = [HttpdnsUtil safeObjectForKey:host dict:self.ipQueryCache];
            
            if (cacheArr.count == 2) {
                return;
            }
            
            if (![EMASTools isValidArray:cacheArr]) {  //当前缓存中无当前域名查询策略
                NSMutableArray *cacheMArr = [NSMutableArray array];
                if (queryType & HttpdnsQueryIPTypeIpv4) {  //ipv4 查询
                    [cacheMArr addObject:QueryCacheIPV4Key];
                }
                
                if (queryType & HttpdnsQueryIPTypeIpv6) {  //ipv6 查询
                    [cacheMArr addObject:QueryCacheIPV6Key];
                }
                
                //如果当前是auto类型，且缓存中无查询策略，则根据ipv6开关来判断
                if (![EMASTools isValidArray:cacheMArr] && queryType == HttpdnsQueryIPTypeAuto) {
                    
                    if ([self isAbleToResolveIPv6Result]) {
                        [cacheMArr addObject:QueryCacheIPV4Key];
                        [cacheMArr addObject:QueryCacheIPV6Key];
                    } else {
                        [cacheMArr addObject:QueryCacheIPV4Key];
                    }
                    
                }
                
                
                [HttpdnsUtil safeAddValue:cacheMArr key:host toDict:self.ipQueryCache];
                
            } else {  //当前缓存中存在该域名的查询策略
                
                NSMutableArray *cacheMArr = [NSMutableArray arrayWithArray:cacheArr];
                if ([cacheArr containsObject:QueryCacheIPV4Key]) {
                    if (queryType & HttpdnsQueryIPTypeIpv6) {
                        [cacheMArr addObject:QueryCacheIPV6Key];
                    }
                } else {
                    if (queryType & HttpdnsQueryIPTypeIpv4) {
                        [cacheMArr addObject:QueryCacheIPV4Key];
                    }
                }
                [HttpdnsUtil safeAddValue:cacheMArr key:host toDict:self.ipQueryCache];
                
            }
        }
        
    }
}


- (HttpdnsQueryIPType)getQueryHostIPType:(NSString *)host {
    
    @synchronized (self) {
        NSArray *cacheArr = [HttpdnsUtil safeObjectForKey:host dict:self.ipQueryCache];
        if ([HttpdnsUtil isValidArray:cacheArr]) {
            
            if (cacheArr.count == 2) {
                return HttpdnsQueryIPTypeIpv4|HttpdnsQueryIPTypeIpv6;
            } else {
                
                if ([cacheArr containsObject:QueryCacheIPV4Key]) {
                    return HttpdnsQueryIPTypeIpv4;
                } else {
                    return HttpdnsQueryIPTypeIpv6;
                }
            }
            
        } else {
            
            if ([self isAbleToResolveIPv6Result]) {
                return HttpdnsQueryIPTypeIpv4 | HttpdnsQueryIPTypeIpv6;
            } else {
                return HttpdnsQueryIPTypeIpv4;
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
