//
//  HTTPDNSCookieManager.m
//  AlicloudHttpDNSTestDemo
//
//  Created by yannan on 2022/4/11.
//  Copyright © 2022 alibaba-inc.com. All rights reserved.
//

#import "HTTPDNSCookieManager.h"


/*

 https://developer.aliyun.com/article/64356


 - (void)connectToUrlStringUsingHTTPDNS:(NSString *)urlString {
     NSURL *url = [NSURL URLWithString:urlString];
     NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
     configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
     NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
     NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
     NSString *ip = [[HttpDnsService sharedInstance] getIpByHostAsync:url.host];
     if (ip) {
         NSLog(@"Get IP(%@) for host(%@) from HTTPDNS Successfully!", ip, url.host);
         NSRange hostFirstRange = [urlString rangeOfString:url.host];
         if (hostFirstRange.location != NSNotFound) {
             NSString *newUrlString = [urlString stringByReplacingCharactersInRange:hostFirstRange withString:ip];
             NSLog(@"New URL: %@", newUrlString);
             request.URL = [NSURL URLWithString:newUrlString];
             [request setValue:url.host forHTTPHeaderField:@"host"];
             // 匹配合适Cookie添加到request中，这里传入的是原生URL
             [request setValue:[[HTTPDNSCookieManager sharedInstance] getRequestCookieHeaderForURL:url] forHTTPHeaderField:@"Cookie"];
             // 删除Cookie
             [[HTTPDNSCookieManager sharedInstance] deleteCookieForURL:url];
         }
     }
     NSURLSessionTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
         if (error) {
             NSLog(@"error: %@", error);
         } else {
             NSLog(@"response: %@", response);
             NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
             // 解析HTTP Response Header，存储cookie
             [[HTTPDNSCookieManager sharedInstance] handleHeaderFields:[httpResponse allHeaderFields] forURL:url];
             NSLog(@"data: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
             NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
         }
     }];
     [task resume];
 }



 */


@interface HTTPDNSCookieManager ()

@property (nonatomic, copy) HTTPDNSCookieFilter cookieFilter;

@end


@implementation HTTPDNSCookieManager

- (instancetype)init {
    if (self = [super init]) {
        /**
            此处设置的Cookie和URL匹配策略比较简单，检查URL.host是否包含Cookie的domain字段
            通过调用setCookieFilter接口设定Cookie匹配策略，
            比如可以设定Cookie的domain字段和URL.host的后缀匹配 | URL是否符合Cookie的path设定
            细节匹配规则可参考RFC 2965 3.3节
         */
        self.cookieFilter = ^BOOL(NSHTTPCookie *cookie, NSURL *URL) {
            if ([URL.host containsString:cookie.domain]) {
                return YES;
            }
            return NO;
        };
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

- (void)setCookieFilter:(HTTPDNSCookieFilter)filter {
    if (filter != nil) {
        self.cookieFilter = filter;
    }
}

- (NSArray<NSHTTPCookie *> *)handleHeaderFields:(NSDictionary *)headerFields forURL:(NSURL *)URL {
    NSArray *cookieArray = [NSHTTPCookie cookiesWithResponseHeaderFields:headerFields forURL:URL];
    if (cookieArray != nil) {
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in cookieArray) {
            if (self.cookieFilter(cookie, URL)) {
                NSLog(@"Add a cookie: %@", cookie);
                [cookieStorage setCookie:cookie];
            }
        }
    }
    return cookieArray;
}

- (NSString *)getRequestCookieHeaderForURL:(NSURL *)URL {
    NSArray *cookieArray = [self searchAppropriateCookies:URL];
    if (cookieArray != nil && cookieArray.count > 0) {
        NSDictionary *cookieDic = [NSHTTPCookie requestHeaderFieldsWithCookies:cookieArray];
        if ([cookieDic objectForKey:@"Cookie"]) {
            return cookieDic[@"Cookie"];
        }
    }
    return nil;
}

- (NSArray *)searchAppropriateCookies:(NSURL *)URL {
    NSMutableArray *cookieArray = [NSMutableArray array];
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
        if (self.cookieFilter(cookie, URL)) {
            NSLog(@"Search an appropriate cookie: %@", cookie);
            [cookieArray addObject:cookie];
        }
    }
    return cookieArray;
}

- (NSInteger)deleteCookieForURL:(NSURL *)URL {
    int delCount = 0;
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
        if (self.cookieFilter(cookie, URL)) {
            NSLog(@"Delete a cookie: %@", cookie);
            [cookieStorage deleteCookie:cookie];
            delCount++;
        }
    }
    return delCount;
}


@end
