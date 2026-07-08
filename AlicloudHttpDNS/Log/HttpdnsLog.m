/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */


#import "HttpdnsLog_Internal.h"
#import <os/lock.h>

static BOOL HttpdnsLogIsEnabled = NO;

// sLogHandler会被业务线程(set/unset)和SDK各日志线程并发访问，
// 必须加锁保证读取方拿到的对象在发消息期间不被释放
static id<HttpdnsLoggerProtocol> sLogHandler;
static os_unfair_lock sLogHandlerLock = OS_UNFAIR_LOCK_INIT;

@implementation HttpdnsLog

+ (void)enableLog {
    HttpdnsLogIsEnabled = YES;
}

+ (void)disableLog {
    HttpdnsLogIsEnabled = NO;
}

+ (BOOL)isEnabled {
    return HttpdnsLogIsEnabled;
}

+ (void)setLogHandler:(id<HttpdnsLoggerProtocol>)handler {
    SEL sel = NSSelectorFromString(@"log:");
    if (handler && [handler respondsToSelector:sel]) {
        // 旧handler放到锁外释放，避免其dealloc回调再进入本类导致死锁
        id<HttpdnsLoggerProtocol> oldHandler;
        os_unfair_lock_lock(&sLogHandlerLock);
        oldHandler = sLogHandler;
        sLogHandler = handler;
        os_unfair_lock_unlock(&sLogHandlerLock);
        oldHandler = nil;
    }
}

+ (void)unsetLogHandler {
    id<HttpdnsLoggerProtocol> oldHandler;
    os_unfair_lock_lock(&sLogHandlerLock);
    oldHandler = sLogHandler;
    sLogHandler = nil;
    os_unfair_lock_unlock(&sLogHandlerLock);
    oldHandler = nil;
}

+ (BOOL)validLogHandler {
    os_unfair_lock_lock(&sLogHandlerLock);
    BOOL valid = (sLogHandler != nil);
    os_unfair_lock_unlock(&sLogHandlerLock);
    return valid;
}

+ (void)outputToLogHandler:(NSString *)logStr {
    // 锁内取局部强引用，保证并发set/unset时正在被调用的handler不会被提前释放
    id<HttpdnsLoggerProtocol> handler;
    os_unfair_lock_lock(&sLogHandlerLock);
    handler = sLogHandler;
    os_unfair_lock_unlock(&sLogHandlerLock);
    if (handler) {
        [handler log:logStr];
    }
}

+ (NSString *)getFormattedDateTimeStr {
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        // 格式只设置一次；NSDateFormatter未被变异时并发stringFromDate:是线程安全的
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    });

    return [dateFormatter stringFromDate:[NSDate date]];
}

@end
