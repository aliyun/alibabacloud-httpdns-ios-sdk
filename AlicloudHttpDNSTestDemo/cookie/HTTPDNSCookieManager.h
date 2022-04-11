//
//  HTTPDNSCookieManager.h
//  AlicloudHttpDNSTestDemo
//
//  Created by yannan on 2022/4/11.
//  Copyright © 2022 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// URL匹配Cookie规则
typedef BOOL (^HTTPDNSCookieFilter)(NSHTTPCookie *, NSURL *);

@interface HTTPDNSCookieManager : NSObject

+ (instancetype)sharedInstance;

/**
 指定URL匹配Cookie策略

 @param filter 匹配器
 */
- (void)setCookieFilter:(HTTPDNSCookieFilter)filter;

/**
 处理HTTP Reponse携带的Cookie并存储

 @param headerFields HTTP Header Fields
 @param URL 根据匹配策略获取查找URL关联的Cookie
 @return 返回添加到存储的Cookie
 */
- (NSArray<NSHTTPCookie *> *)handleHeaderFields:(NSDictionary *)headerFields forURL:(NSURL *)URL;

/**
 匹配本地Cookie存储，获取对应URL的request cookie字符串

 @param URL 根据匹配策略指定查找URL关联的Cookie
 @return 返回对应URL的request Cookie字符串
 */
- (NSString *)getRequestCookieHeaderForURL:(NSURL *)URL;

/**
 删除存储cookie

 @param URL 根据匹配策略查找URL关联的cookie
 @return 返回成功删除cookie数
 */
- (NSInteger)deleteCookieForURL:(NSURL *)URL;

@end

NS_ASSUME_NONNULL_END
