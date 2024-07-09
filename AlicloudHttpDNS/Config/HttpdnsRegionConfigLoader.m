//
//  HttpdnsRegionConfigLoader.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/6/16.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsRegionConfigLoader.h"
#import "HttpdnsPublicConstant.h"

static NSString *const kServiceV4Key = @"ALICLOUD_HTTPDNS_SERVICE_HOST_V4_KEY";
static NSString *const kUpdateV4FallbackHostKey = @"ALICLOUD_HTTPDNS_UPDATE_HOST_V4_KEY";
static NSString *const kServiceV6Key = @"ALICLOUD_HTTPDNS_SERVICE_HOST_V6_KEY";
static NSString *const kUpdateV6FallbackHostKey = @"ALICLOUD_HTTPDNS_UPDATE_HOST_V6_KEY";

static NSArray<NSString *> *ALICLOUD_HTTPDNS_AVAILABLE_REGION_LIST = nil;

@interface HttpdnsRegionConfigLoader ()

@property (nonatomic, strong) NSDictionary *regionConfig;

@end

@implementation HttpdnsRegionConfigLoader

+ (void)initialize {
    ALICLOUD_HTTPDNS_AVAILABLE_REGION_LIST = @[
        ALICLOUD_HTTPDNS_DEFAULT_REGION_KEY,
        ALICLOUD_HTTPDNS_HONGKONG_REGION_KEY,
        ALICLOUD_HTTPDNS_SINGAPORE_REGION_KEY,
        ALICLOUD_HTTPDNS_GERMANY_REGION_KEY,
        ALICLOUD_HTTPDNS_AMERICA_REGION_KEY
    ];
}

+ (instancetype)sharedInstance {
    static HttpdnsRegionConfigLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HttpdnsRegionConfigLoader alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self loadRegionConfig];
    }
    return self;
}

+ (NSArray<NSString *> *)getAvailableRegionList {
    return ALICLOUD_HTTPDNS_AVAILABLE_REGION_LIST;
}

- (void)loadRegionConfig {
    self.regionConfig = @{
        ALICLOUD_HTTPDNS_DEFAULT_REGION_KEY: @{
            kServiceV4Key: @[@"203.107.1.1", @"203.107.1.97", @"203.107.1.100", @"203.119.238.240", @"106.11.25.239", @"59.82.99.47"],
            kUpdateV4FallbackHostKey: @[@"resolvers-cn.httpdns.aliyuncs.com"],
            kServiceV6Key: @[@"2401:b180:7001::31d", @"2401:b180:2000:30::1c", @"2401:b180:2000:20::10", @"2401:b180:2000:30::1c"],
            kUpdateV6FallbackHostKey: @[@"resolvers-cn.httpdns.aliyuncs.com"]
        },
        ALICLOUD_HTTPDNS_HONGKONG_REGION_KEY: @{
            kServiceV4Key: @[@"47.56.234.194", @"47.56.119.115"],
            kUpdateV4FallbackHostKey: @[@"resolvers-hk.httpdns.aliyuncs.com"],
            kServiceV6Key: @[@"240b:4000:f10::178", @"240b:4000:f10::188"],
            kUpdateV6FallbackHostKey: @[@"resolvers-hk.httpdns.aliyuncs.com"]
        },
        ALICLOUD_HTTPDNS_SINGAPORE_REGION_KEY: @{
            kServiceV4Key: @[@"161.117.200.122", @"47.74.222.190"],
            kUpdateV4FallbackHostKey: @[@"resolvers-sg.httpdns.aliyuncs.com"],
            kServiceV6Key: @[@"240b:4000:f10::178", @"240b:4000:f10::188"],
            kUpdateV6FallbackHostKey: @[@"resolvers-sg.httpdns.aliyuncs.com"]
        },
        ALICLOUD_HTTPDNS_GERMANY_REGION_KEY: @{
            kServiceV4Key: @[@"47.89.80.182", @"47.246.146.77"],
            kUpdateV4FallbackHostKey: @[@"resolvers-de.httpdns.aliyuncs.com"],
            kServiceV6Key: @[@"2404:2280:3000::176", @"2404:2280:3000::188"],
            kUpdateV6FallbackHostKey: @[@"resolvers-de.httpdns.aliyuncs.com"]
        },
        ALICLOUD_HTTPDNS_AMERICA_REGION_KEY: @{
            kServiceV4Key: @[@"47.246.131.175", @"47.246.131.141"],
            kUpdateV4FallbackHostKey: @[@"resolvers-us.httpdns.aliyuncs.com"],
            kServiceV6Key: @[@"2404:2280:4000::2bb", @"2404:2280:4000::23e"],
            kUpdateV6FallbackHostKey: @[@"resolvers-us.httpdns.aliyuncs.com"]
        }
    };
}

- (NSArray *)getSeriveV4HostList:(NSString *)region {
    return [self.regionConfig mutableArrayValueForKeyPath:[NSString stringWithFormat:@"%@.%@", region, kServiceV4Key]];
}

- (NSArray *)getUpdateV4FallbackHostList:(NSString *)region {
    return [self.regionConfig mutableArrayValueForKeyPath:[NSString stringWithFormat:@"%@.%@", region, kUpdateV4FallbackHostKey]];
}

- (NSArray *)getSeriveV6HostList:(NSString *)region {
    return [self.regionConfig mutableArrayValueForKeyPath:[NSString stringWithFormat:@"%@.%@", region, kServiceV6Key]];
}

- (NSArray *)getUpdateV6FallbackHostList:(NSString *)region {
    return [self.regionConfig mutableArrayValueForKeyPath:[NSString stringWithFormat:@"%@.%@", region, kUpdateV6FallbackHostKey]];
}

@end
