//
//  HttpdnsIPv6Manager.h
//  AlicloudHttpDNS
//
//  Created by junmo on 2018/8/31.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsService.h"

@interface HttpdnsIPv6Manager : NSObject

+ (instancetype)sharedInstance;

/**
 开启/关闭IPv6解析结果（域名解析返回IPv6地址）
 */
- (void)setIPv6ResultEnable:(BOOL)enable;

/**
 处理queryType参数
 */
- (NSString *)appendQueryTypeToURL:(NSString *)originURL queryType:(HttpdnsQueryIPType)queryType;

/**
 判断是否支持返回IPv6解析结果
 */
- (BOOL)isAbleToResolveIPv6Result;

@end
