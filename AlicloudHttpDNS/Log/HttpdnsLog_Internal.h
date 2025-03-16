//
//  HttpdnsLog_Internal.h
//  AlicloudHttpDNS
//
//  Created by junmo on 2018/12/19.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsLog.h"
#import "HttpdnsLoggerDelegate.h"
#import <pthread/pthread.h>

// logHandler输出日志，不受日志开关影响
#define HttpdnsLogDebug(frmt, ...) \
if ([HttpdnsLog validLogHandler]) { \
    @try { \
        uint64_t tid = 0; \
        pthread_threadid_np(NULL, &tid); \
        NSString *logFormat = [NSString stringWithFormat:@"%s", frmt]; \
        NSString *logStr = [NSString stringWithFormat:@"[%llu] %@", tid, [NSString stringWithFormat:logFormat, ##__VA_ARGS__, nil]]; \
        [HttpdnsLog outputToLogHandler:logStr]; \
    } @catch (NSException *exception){ \
    } \
} \
if ([HttpdnsLog isEnabled]) { \
    @try { \
        uint64_t tid = 0; \
        pthread_threadid_np(NULL, &tid); \
        NSLog((@"%@ HTTPDNSSDKLOG [%llu] - " frmt), [HttpdnsLog getFormattedDateTimeStr], tid, ##__VA_ARGS__); \
    } @catch (NSException *exception){ \
    } \
}


@interface HttpdnsLog ()

+ (void)setLogHandler:(id<HttpdnsLoggerProtocol>)handler;
+ (void)unsetLogHandler;
+ (BOOL)validLogHandler;
+ (void)outputToLogHandler:(NSString *)logStr;

+ (NSString *)getFormattedDateTimeStr;


@end
