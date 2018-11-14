//
//  HttpdnsIPv6Manager.m
//  AlicloudHttpDNS
//
//  Created by junmo on 2018/8/31.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import <AlicloudUtils/AlicloudIPv6Adapter.h>
#import <AlicloudUtils/EMASTools.h>
#import "HttpdnsPersistenceUtils.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsIPv6Manager.h"
#import "HttpDnsHitService.h"

@interface HttpdnsIPv6Manager()

@property (nonatomic, assign) BOOL usersetIPv6ResultEnable;
@property (nonatomic, assign) BOOL usersetIPv6ServiceEnable;
@property (nonatomic, assign) BOOL ipv6ServiceEnable;
@property (nonatomic, assign) BOOL ipv6ServiceMask;
@property (nonatomic, copy) NSString *ipv6ServiceStopFlagPath;
@property (nonatomic, strong) dispatch_queue_t syncQueue;
@property (nonatomic, strong) dispatch_queue_t storeSyncQueue;
@property (nonatomic, strong) NSMutableDictionary *storeIPv6Results;

@end

@implementation HttpdnsIPv6Manager

- (instancetype)init {
    if (self = [super init]) {
        _usersetIPv6ResultEnable = NO;
        _usersetIPv6ServiceEnable = NO;
        _ipv6ServiceEnable = NO;
        _ipv6ServiceMask = NO;
        _syncQueue = dispatch_queue_create("com.httpdns.ipv6.manager", NULL);
        _storeSyncQueue = dispatch_queue_create("com.httpdns.ipv6.store", NULL);
        _storeIPv6Results = [NSMutableDictionary dictionary];
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
    [HttpDnsHitService bizIPv6Enable];
}

- (NSString *)assembleIPv6ResultURL:(NSString *)originURL {
    if (![EMASTools isValidString:originURL]) {
        return originURL;
    }
    // URLEncode(4,6) = 4%2c6
    return [NSString stringWithFormat:@"%@&query=4%%2c6", originURL];
}

- (BOOL)isAbleToResolveIPv6Result {
    return _usersetIPv6ResultEnable;
}

- (void)storeIPv6ResolveRes:(NSArray<HttpdnsIpObject *> *)ipv6Array forHost:(NSString *)host {
    if (![EMASTools isValidString:host] || ![EMASTools isValidArray:ipv6Array]) {
        return ;
    }
    dispatch_sync(_storeSyncQueue, ^{
        [_storeIPv6Results setObject:ipv6Array forKey:host];
    });
}

- (NSArray<HttpdnsIpObject *> *)getIPv6ObjectArrayForHost:(NSString *)host {
    __block NSArray *res = nil;
    dispatch_sync(_storeSyncQueue, ^{
        res = [_storeIPv6Results objectForKey:host];
    });
    return res;
}

- (NSArray<NSString *> *)getIP6StringsByHost:(NSString *)host {
    NSArray<HttpdnsIpObject *> *ipRecords = [self getIPv6ObjectArrayForHost:host];
    if (!ipRecords) {
        return nil;
    }
    NSMutableArray<NSString *> *ip6s = [NSMutableArray arrayWithCapacity:ipRecords.count];
    for (HttpdnsIpObject *ipObject in ipRecords) {
        @try {
            [ip6s addObject:ipObject.ip];
        } @catch (NSException *exception) {}
    }
    return [ip6s copy];
}

@end
