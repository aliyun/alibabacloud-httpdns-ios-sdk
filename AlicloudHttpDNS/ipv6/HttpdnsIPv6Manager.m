//
//  HttpdnsIPv6Manager.m
//  AlicloudHttpDNS
//
//  Created by junmo on 2018/8/31.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import "AlicloudIPv6Adapter.h"
#import "HttpdnsIPv6Manager.h"
#import "HttpdnsUtil.h"



static NSString *const QueryCacheIPV4Key = @"QueryCacheIPV4Key";
static NSString *const QueryCacheIPV6Key = @"QueryCacheIPV6Key";

@interface HttpdnsIPv6Manager()

@property (nonatomic, assign) BOOL usersetIPv6ResultEnable;


@end

@implementation HttpdnsIPv6Manager

- (instancetype)init {
    if (self = [super init]) {
        _usersetIPv6ResultEnable = YES;
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
}

- (NSString *)appendQueryTypeToURL:(NSString *)originURL queryType:(HttpdnsQueryIPType)queryType {
    if (queryType & HttpdnsQueryIPTypeIpv4 && queryType & HttpdnsQueryIPTypeIpv6) {
        return [NSString stringWithFormat:@"%@&query=%@", originURL, [HttpdnsUtil URLEncodedString:@"4,6"]];
    } else if (queryType & HttpdnsQueryIPTypeIpv6) {
        return [NSString stringWithFormat:@"%@&query=%@", originURL, @"6"];
    } else {
        return originURL;
    }
}

- (BOOL)isAbleToResolveIPv6Result {
    return _usersetIPv6ResultEnable;
}

@end
