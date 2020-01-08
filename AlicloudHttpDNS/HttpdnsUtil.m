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

#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "CommonCrypto/CommonCrypto.h"
#import "arpa/inet.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "UIApplication+ABSHTTPDNSSetting.h"
#import "HttpdnsConstants.h"
#import "HttpdnsRequest.h"

@implementation HttpdnsUtil

+ (int64_t)currentEpochTimeInSecond {
    return (int64_t)[[[NSDate alloc] init] timeIntervalSince1970];
}

+ (NSString *)currentEpochTimeInSecondString {
    return [NSString stringWithFormat:@"%lld", [HttpdnsUtil currentEpochTimeInSecond]];
}

+ (BOOL)isAnIP:(NSString *)candidate {
    const char *utf8 = [candidate UTF8String];
    
    // Check valid IPv4.
    struct in_addr dst;
    int success = inet_pton(AF_INET, utf8, &(dst.s_addr));
    if (success != 1) {
        // Check valid IPv6.
        struct in6_addr dst6;
        success = inet_pton(AF_INET6, utf8, &dst6);
    }
    return (success == 1);
}

+ (BOOL)isAHost:(NSString *)host {
    static dispatch_once_t once_token;
    static NSRegularExpression *hostExpression = nil;
    dispatch_once(&once_token, ^{
        hostExpression = [[NSRegularExpression alloc] initWithPattern:@"^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    
    if (!host.length) {
        return NO;
    }
    NSTextCheckingResult *checkResult = [hostExpression firstMatchInString:host options:0 range:NSMakeRange(0, [host length])];
    if (checkResult.range.length == [host length]) {
        return YES;
    } else {
        return NO;
    }
}

+ (NSString *)getRequestHostFromString:(NSString *)string {
    NSString *requestHost = string;
    // Adapt to IPv6-only network.
    if (([self isAnIP:string]) && ([[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork])) {
        requestHost = [NSString stringWithFormat:@"[%@]", [[AlicloudIPv6Adapter getInstance] handleIpv4Address:string]];
    }
    return requestHost;
}

+ (void)warnMainThreadIfNecessary {
    if ([NSThread isMainThread]) {
        HttpdnsLogDebug("Warning: A long-running Paas operation is being executed on the main thread.");
    }
}

//wifi是否可用
+ (BOOL)isWifiEnable {
    BOOL isReachableViaWiFi =  [[AlicloudReachabilityManager shareInstance] isReachableViaWifi];
    return isReachableViaWiFi;
}

//蜂窝移动网络是否可用
+ (BOOL)isCarrierConnectEnable {
    BOOL isReachableViaWWAN = [[AlicloudReachabilityManager shareInstance] isReachableViaWWAN];
    return isReachableViaWWAN;
}

+ (BOOL)isAbleToRequest {
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    if (!sharedService.accountID || sharedService.accountID == 0) {
        return NO;
    }
    return YES;
}

+ (NSDictionary *)getValidDictionaryFromJson:(id)jsonValue {
    NSDictionary *dictionaryValueFromJson = nil;
    if ([jsonValue isKindOfClass:[NSDictionary class]]) {
        if ([(NSDictionary *)jsonValue allKeys].count > 0) {
            NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithDictionary:jsonValue];
            @try {
                [self removeNSNullValueFromDictionary:mutableDict];
            } @catch (NSException *exception) {}
            dictionaryValueFromJson = [jsonValue copy];
        }
    }
    return dictionaryValueFromJson;
}

+ (void)removeNSNullValueFromArray:(NSMutableArray *)array {
    NSMutableArray *objToRemove = nil;
    NSMutableIndexSet *indexToReplace = [[NSMutableIndexSet alloc] init];
    NSMutableArray *objForReplace = [[NSMutableArray alloc] init];
    for (int i = 0; i < array.count; ++i) {
        id value = [array objectAtIndex:i];
        if ([value isKindOfClass:[NSNull class]]) {
            if (!objToRemove) {
                objToRemove = [[NSMutableArray alloc] init];
            }
            [objToRemove addObject:value];
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithDictionary:value];
            [self removeNSNullValueFromDictionary:mutableDict];
            [indexToReplace addIndex:i];
            [objForReplace addObject:mutableDict];
        } else if ([value isKindOfClass:[NSArray class]]) {
            NSMutableArray *v = [value mutableCopy];
            [self removeNSNullValueFromArray:v];
            [indexToReplace addIndex:i];
            [objForReplace addObject:v];
        }
    }
    [array replaceObjectsAtIndexes:indexToReplace withObjects:objForReplace];
    if (objToRemove) {
        [array removeObjectsInArray:objToRemove];
    }
}

+ (void)removeNSNullValueFromDictionary:(NSMutableDictionary *)dict {
    for (id key in [dict allKeys]) {
        id value = [dict objectForKey:key];
        if ([value isKindOfClass:[NSNull class]]) {
            [dict removeObjectForKey:key];
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithDictionary:value];
            [self removeNSNullValueFromDictionary:mutableDict];
            [dict setObject:mutableDict forKey:key];
        } else if ([value isKindOfClass:[NSArray class]]) {
            NSMutableArray *v = [value mutableCopy];
            [self removeNSNullValueFromArray:v];
            [dict setObject:v forKey:key];
        }
    }
}

+ (BOOL)isValidArray:(id)notValidArray {
    if (!notValidArray) {
        return NO;
    }
    BOOL isKindOf = NO;
    @try {
        isKindOf = [notValidArray isKindOfClass:[NSArray class]];
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
    }
    if (!isKindOf) {
        return NO;
    }
    __block NSInteger arrayCount = 0;
    @synchronized (self) {
        @try {
            arrayCount = [(NSArray *)notValidArray count];
        } @catch (NSException *exception) {
            NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
        }
    }
    if (arrayCount == 0) {
        return NO;
    }
    return YES;
}

+ (BOOL)isValidString:(id)notValidString {
    if (!notValidString) {
        return NO;
    }
    BOOL isKindOf = NO;
    @try {
        isKindOf = [notValidString isKindOfClass:[NSString class]];
    } @catch (NSException *exception) {}
    if (!isKindOf) {
        return NO;
    }
    
    NSInteger stringLength = 0;
    @try {
        stringLength = [notValidString length];
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
    }
    if (stringLength == 0) {
        return NO;
    }
    return YES;
}

+ (BOOL)isValidJSON:(id)JSON {
    BOOL isValid;
    @try {
        isValid = ([JSON isKindOfClass:[NSDictionary class]] || [JSON isKindOfClass:[NSArray class]]);
    } @catch (NSException *exception) {}
    return isValid;
}
+ (BOOL)isValidDictionary:(id)obj {
    if ((obj != nil) && ([obj isKindOfClass:[NSDictionary class]])) {
        NSDictionary *dic = obj;
        return (dic.count > 0);
    }
    return NO;
}

+ (id)convertJsonStringToObject:(NSString *)jsonStr {
    if ([self isValidString:jsonStr]) {
        return [self convertJsonDataToObject:[jsonStr dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return nil;
}

+ (id)convertJsonDataToObject:(NSData *)jsonData {
    if (jsonData) {
        NSError *error;
        id jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&error];
        if (!error) {
            return jsonObj;
        }
    }
    return nil;
}

+ (NSString *)getMD5StringFrom:(NSString *)originString {
    const char * pointer = [originString UTF8String];
    unsigned char md5Buffer[CC_MD5_DIGEST_LENGTH];
    
    CC_MD5(pointer, (CC_LONG)strlen(pointer), md5Buffer);
    
    NSMutableString *string = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [string appendFormat:@"%02x",md5Buffer[i]];
    
    return [string copy];
}

+ (NSError *)getErrorFromError:(NSError *)error statusCode:(NSInteger)statusCode json:(NSDictionary *)json isHTTPS:(BOOL)isHTTPS {
    NSError *errorStrong = [error copy];
    if (statusCode != 200) {
        HttpdnsLogDebug("ReponseCode %ld.", (long)statusCode);
        if (errorStrong) {
            NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  @"Response code not 200, and parse response message error", ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY,
                                  [NSString stringWithFormat:@"%ld", (long)statusCode], @"ResponseCode", nil];
            errorStrong = [NSError errorWithDomain:@"httpdns.request.lookupAllHostsFromServer-HTTPS" code:10002 userInfo:dict];
        } else {
            NSString *errCode = @"";
            @try {
                errCode = [json objectForKey:@"code"];
            } @catch (NSException *exception) {}
            NSDictionary *dict = nil;
            if ([HttpdnsUtil isValidString:errCode]) {
                dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                        errCode, ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY, nil];
            }
            
            NSString *domainString = [NSString stringWithFormat:@"httpdns.request.lookupAllHostsFromServer-%@", isHTTPS? @"HTTPS": @"HTTP"];
            NSInteger code = isHTTPS ? ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE : ALICLOUD_HTTPDNS_HTTP_COMMON_ERROR_CODE;
            errorStrong = [NSError errorWithDomain:domainString code:code userInfo:dict];
        }
    } else {
        HttpdnsLogDebug("Response code 200.");
    }
    return errorStrong;
}

/**
 生成sessionId
 App打开生命周期只生成一次，不做持久化
 sessionId为12位，采用base62编码
 
 @return 返回sessionId
 */
+ (NSString *)generateSessionID {
    static NSString *sessionId = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        NSUInteger length = alphabet.length;
        if (![HttpdnsUtil isValidString:sessionId]) {
            NSMutableString *mSessionId = [NSMutableString string];
            for (int i = 0; i < 12; i++) {
                [mSessionId appendFormat:@"%@", [alphabet substringWithRange:NSMakeRange(arc4random() % length, 1)]];
            }
            sessionId = [mSessionId copy];
        }
    });
    return sessionId;
}

+ (void)safeAddObject:(id)object toArray:(NSMutableArray *)mutableArray {
    @try {
        @synchronized(self) {
            [mutableArray addObject:object];
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
    }
}

+ (void)safeAddValue:(id)value key:(NSString *)key toDict:(NSMutableDictionary *)dict {
    @try {
        @synchronized (self) {
            [dict setObject:value forKey:key];
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
    }
}

+ (void)safeRemoveAllObjectsFromDict:(NSMutableDictionary *)dict {
    @try {
        @synchronized (self) {
            [dict removeAllObjects];
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
    }
}

+ (id)safeAllKeysFromDict:(NSDictionary *)dict {
    NSArray *keysArray;
    @synchronized (self) {
        keysArray = [dict allKeys];
    }
    return keysArray;
}

+ (NSInteger)safeCountFromDict:(NSDictionary *)dict {
    NSInteger dictCount;
    @synchronized (self) {
        dictCount = [dict count];
    }
    return dictCount;
}

+ (id)safeObjectForKey:(NSString *)key dict:(NSDictionary *)dict {
    id object;
    @try {
        @synchronized (self) {
            object = [dict objectForKey:key];
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
    }
    return object;
}

+ (id)safeOjectAtIndex:(int)index array:(NSArray *)array {
    id object;
    @try {
        @synchronized (self) {
            object = array[index];
        }
    } @catch (NSException *exception) {
        NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
    }
    return object;
}

+ (id)safeObjectAtIndexOrTheFirst:(int)index array:(NSArray *)array defaultValue:(id)defaultValue {
    id object = defaultValue;
    @try {
        @synchronized (self) {
            object = array[index];
        }
    } @catch (NSException *exception) {
        @try {
            @synchronized (self) {
                object = array[0];
            }
        } @catch (NSException *exception) {
            NSLog(@"🔴类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
        }
    }
    return object;
}

@end
