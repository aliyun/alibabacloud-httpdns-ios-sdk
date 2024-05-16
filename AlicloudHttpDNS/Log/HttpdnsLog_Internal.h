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
        NSLog((@"HTTPDNSSDKLOG - " frmt), ##__VA_ARGS__);\
    } @catch (NSException *exception){\
    }\
}


//这里的日志输出是只针对 DNS 测试环境下提供给测试同学查看数据使用
#define HttpdnsLogDebug_TestOnly(frmt, ...)\
if ([HttpdnsLog validTestLogHandler]) {\
    NSString *logFormat = [NSString stringWithFormat:@"%@", frmt];\
    NSString *logStr = [NSString stringWithFormat:logFormat, ##__VA_ARGS__, nil];\
    [HttpdnsLog outputTestToLogHandler:logStr];\
}



@protocol HttpdnsLog_testOnly_protocol <NSObject>

- (void)testLog:(NSString *)testLog;

@end



@interface HttpdnsLog ()

+ (void)setLogHandler:(id<HttpdnsLoggerProtocol>)handler;
+ (BOOL)validLogHandler;
+ (void)outputToLogHandler:(NSString *)logStr;


+ (void)setTestLogHandler:(id<HttpdnsLog_testOnly_protocol>)handler;
+ (BOOL)validTestLogHandler;
+ (void)outputTestToLogHandler:(NSString *)logStr;


@end
