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

#import <UIKit/UIKit.h>
#import "HttpdnsUtil.h"
#import "HttpdnsLog_Internal.h"
#import "CommonCrypto/CommonCrypto.h"
#import "arpa/inet.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsInternalConstant.h"
#import "HttpdnsHostResolver.h"
#import "HttpdnsPublicConstant.h"
#import "httpdnsReachability.h"

@implementation HttpdnsUtil

+ (int64_t)currentEpochTimeInSecond {
    return (int64_t)[[[NSDate alloc] init] timeIntervalSince1970];
}

+ (NSString *)currentEpochTimeInSecondString {
    return [NSString stringWithFormat:@"%lld", [HttpdnsUtil currentEpochTimeInSecond]];
}


+ (BOOL)isIPv4Address:(NSString *)addr {
    if (!addr) {
        return NO;
    }
    struct in_addr dst;
    return inet_pton(AF_INET, [addr UTF8String], &(dst.s_addr)) == 1;
}

+ (BOOL)isIPv6Address:(NSString *)addr {
    if (!addr) {
        return NO;
    }
    struct in6_addr dst6;
    return inet_pton(AF_INET6, [addr UTF8String], &dst6) == 1;
}

+ (BOOL)isAnIP:(NSString *)candidate {
    if ([self isIPv4Address:candidate]) {
        return YES;
    }
    if ([self isIPv6Address:candidate]) {
        return YES;
    }
    return NO;
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

+ (void)warnMainThreadIfNecessary {
    if ([NSThread isMainThread]) {
        HttpdnsLogDebug("Warning: A long-running Paas operation is being executed on the main thread.");
    }
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

+ (BOOL)isEmptyArray:(NSArray *)inputArr {
    if (!inputArr) {
        return YES;
    }
    return [inputArr count] == 0;
}

+ (BOOL)isNotEmptyArray:(NSArray *)inputArr {
    return ![self isEmptyArray:inputArr];
}

+ (BOOL)isEmptyString:(NSString *)inputStr {
    if (!inputStr) {
        return YES;
    }
    return [inputStr length] == 0;
}

+ (BOOL)isNotEmptyString:(NSString *)inputStr {
    return ![self isEmptyString:inputStr];
}

+ (BOOL)isValidJSON:(id)JSON {
    BOOL isValid;
    @try {
        isValid = ([JSON isKindOfClass:[NSDictionary class]] || [JSON isKindOfClass:[NSArray class]]);
    } @catch (NSException *ignore) {
    }
    return isValid;
}

+ (BOOL)isEmptyDictionary:(NSDictionary *)inputDict {
    if (!inputDict) {
        return YES;
    }
    return [inputDict count] == 0;
}

+ (BOOL)isNotEmptyDictionary:(NSDictionary *)inputDict {
    return ![self isEmptyDictionary:inputDict];
}

+ (NSArray *)joinArrays:(NSArray *)array1 withArray:(NSArray *)array2 {
    NSMutableArray *resultArray = [array1 mutableCopy];
    [resultArray addObjectsFromArray:array2];
    return [resultArray copy];
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

+ (NSString *)URLEncodedString:(NSString *)str {
    if (str) {
        return [str stringByAddingPercentEncodingWithAllowedCharacters:
                [NSCharacterSet characterSetWithCharactersInString:@"!*'();:@&=+$,/?%#[]\""].invertedSet];
    }
    return nil;
}

/**
 生成sessionId
 App打开生命周期只生成一次，不做持久化
 sessionId为12位，采用base62编码
 */
+ (NSString *)generateSessionID {
    static NSString *sessionId = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        NSUInteger length = alphabet.length;
        if (![HttpdnsUtil isNotEmptyString:sessionId]) {
            NSMutableString *mSessionId = [NSMutableString string];
            for (int i = 0; i < 12; i++) {
                [mSessionId appendFormat:@"%@", [alphabet substringWithRange:NSMakeRange(arc4random() % length, 1)]];
            }
            sessionId = [mSessionId copy];
        }
    });
    return sessionId;
}

+ (NSString *)generateUserAgent {
    UIDevice *device = [UIDevice currentDevice];
    NSString *systemName = [device systemName];
    NSString *systemVersion = [device systemVersion];
    NSString *model = [device model];

    NSString *userAgent = [NSString stringWithFormat:@"HttpdnsSDK/%@ (%@; iOS %@; %@)", HTTPDNS_IOS_SDK_VERSION, model, systemVersion, systemName];

    return userAgent;
}

@end
