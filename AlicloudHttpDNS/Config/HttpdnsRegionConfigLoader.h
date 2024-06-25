//
//  HttpdnsRegionConfigLoader.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/6/16.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HttpdnsRegionConfigLoader : NSObject

+ (instancetype)sharedInstance;

+ (NSArray<NSString *> *)getAvailableRegionList;

- (NSArray *)getSeriveV4HostList:(NSString *)region;

- (NSArray *)getUpdateV4FallbackHostList:(NSString *)region;

- (NSArray *)getSeriveV6HostList:(NSString *)region;

- (NSArray *)getUpdateV6FallbackHostList:(NSString *)region;

@end

NS_ASSUME_NONNULL_END
