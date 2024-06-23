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
static NSString *const kUpdateV4Key = @"ALICLOUD_HTTPDNS_UPDATE_HOST_V4_KEY";
static NSString *const kServiceV6Key = @"ALICLOUD_HTTPDNS_SERVICE_HOST_V6_KEY";
static NSString *const kUpdateV6Key = @"ALICLOUD_HTTPDNS_UPDATE_HOST_V6_KEY";

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
        ALICLOUD_HTTPDNS_GERMANY_REGION_KEY
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
    NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"region_config" ofType:@"plist"];
    self.regionConfig = [NSDictionary dictionaryWithContentsOfFile:filePath];
}

- (NSArray *)getSeriveV4HostList:(NSString *)region {
    return [self.regionConfig mutableArrayValueForKeyPath:[NSString stringWithFormat:@"%@.%@", region, kServiceV4Key]];
}

- (NSArray *)getUpdateV4HostList:(NSString *)region {
    return [self.regionConfig mutableArrayValueForKeyPath:[NSString stringWithFormat:@"%@.%@", region, kUpdateV4Key]];
}

- (NSArray *)getSeriveV6HostList:(NSString *)region {
    return [self.regionConfig mutableArrayValueForKeyPath:[NSString stringWithFormat:@"%@.%@", region, kServiceV6Key]];
}

- (NSArray *)getUpdateV6HostList:(NSString *)region {
    return [self.regionConfig mutableArrayValueForKeyPath:[NSString stringWithFormat:@"%@.%@", region, kUpdateV6Key]];
}

@end
