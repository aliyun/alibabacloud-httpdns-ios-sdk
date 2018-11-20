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

@interface HttpdnsIPv6Manager()

@property (nonatomic, assign) BOOL usersetIPv6ResultEnable;

@end

@implementation HttpdnsIPv6Manager

- (instancetype)init {
    if (self = [super init]) {
        _usersetIPv6ResultEnable = NO;
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

@end
