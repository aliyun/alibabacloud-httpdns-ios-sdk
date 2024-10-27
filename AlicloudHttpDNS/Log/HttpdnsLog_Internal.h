//
//  HttpdnsLog_Internal.h
//  AlicloudHttpDNS
//
//  Created by junmo on 2018/12/19.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsLoggerDelegate.h"
#import "HttpdnsLog.h"

// logHandler输出日志，不受日志开关影响
#define HttpdnsLogDebug(frmt, ...)\
if ([HttpdnsLog validLogHandler]) {\
    @try {\
        NSString *logFormat = [NSString stringWithFormat:@"%s", frmt];\
        NSString *logStr = [NSString stringWithFormat:logFormat, ##__VA_ARGS__, nil];\
        [HttpdnsLog outputToLogHandler:logStr];\
    } @catch (NSException *exception){\
    }\
}\
if ([HttpdnsLog isEnabled]) {\
    @try {\
        NSLog((@"%@ HTTPDNSSDKLOG - " frmt), [HttpdnsLog getFormattedDateTimeStr], ##__VA_ARGS__);\
    } @catch (NSException *exception){\
    }\
}


@interface HttpdnsLog ()

+ (void)setLogHandler:(id<HttpdnsLoggerProtocol>)handler;
+ (BOOL)validLogHandler;
+ (void)outputToLogHandler:(NSString *)logStr;

+ (NSString *)getFormattedDateTimeStr;


@end
