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
#import "HttpdnsLog.h"
#import "CommonCrypto/CommonCrypto.h"
#import "arpa/inet.h"
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsServiceProvider_Internal.h"

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
    if ([AlicloudReachabilityManager shareInstance].currentNetworkStatus == AlicloudNotReachable) {
        return NO;
    }
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
    if (![notValidArray isKindOfClass:[NSArray class]]) {
        return NO;
    }
    NSInteger arrayCount = 0;
    @try {
        arrayCount = [(NSArray *)notValidArray count];
    } @catch (NSException *exception) {}
    if (arrayCount == 0) {
        return NO;
    }
    return YES;
}

+ (BOOL)isValidString:(id)notValidString {
    if (!notValidString) {
        return NO;
    }
    if (![notValidString isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSInteger stringLength = 0;
    @try {
        stringLength = [notValidString length];
    } @catch (NSException *exception) {}
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

@end
