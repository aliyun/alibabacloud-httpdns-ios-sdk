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
#import "HttpdnsPublicConstant.h"
#import "httpdnsReachability.h"
#import "HttpdnsInternalConstant.h"

@implementation HttpdnsUtil

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

+ (NSData *)encryptDataAESCBC:(NSData *)plaintext
                      withKey:(NSData *)key
                        error:(NSError **)error {
    // 检查输入参数
    if (plaintext == nil || [plaintext length] == 0 || key == nil || [key length] != kCCKeySizeAES128) {
        if (error) {
            *error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                         code:ALICLOUD_HTTPDNS_ENCRYPT_INVALID_PARAMS_ERROR_CODE
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid input parameters"}];
        }
        return nil;
    }

    // 为CBC模式生成128bit(16字节)的随机IV
    NSMutableData *iv = [NSMutableData dataWithLength:kCCBlockSizeAES128];
    int result = SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, iv.mutableBytes);
    if (result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                         code:ALICLOUD_HTTPDNS_ENCRYPT_RANDOM_IV_ERROR_CODE
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate random IV"}];
        }
        return nil;
    }

    // 计算加密后的数据长度 (可能需要填充)
    size_t bufferSize = [plaintext length] + kCCBlockSizeAES128;
    size_t encryptedSize = 0;

    // 创建输出缓冲区
    NSMutableData *cipherData = [NSMutableData dataWithLength:bufferSize];

    // 执行加密
    // AES中PKCS5Padding与PKCS7Padding相同
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt,
                                         kCCAlgorithmAES,
                                         kCCOptionPKCS7Padding,
                                         [key bytes],
                                         [key length],
                                         [iv bytes],
                                         [plaintext bytes],
                                         [plaintext length],
                                         [cipherData mutableBytes],
                                         [cipherData length],
                                         &encryptedSize);

    if (cryptStatus != kCCSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                         code:ALICLOUD_HTTPDNS_ENCRYPT_FAILED_ERROR_CODE
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Encryption failed with status: %d", cryptStatus]}];
        }
        return nil;
    }

    // 调整加密数据的长度，只保留实际加密内容
    [cipherData setLength:encryptedSize];

    // 将IV和加密数据合并在一起
    NSMutableData *resultData = [NSMutableData dataWithData:iv];
    [resultData appendData:cipherData];

    return resultData;
}

+ (NSString *)hexStringFromData:(NSData *)data {
    if (!data || data.length == 0) {
        return nil;
    }

    NSMutableString *hexString = [NSMutableString stringWithCapacity:data.length * 2];
    const unsigned char *bytes = data.bytes;

    for (NSInteger i = 0; i < data.length; i++) {
        [hexString appendFormat:@"%02x", bytes[i]];
    }

    return [hexString copy];
}

+ (NSData *)dataFromHexString:(NSString *)hexString {
    if (!hexString || hexString.length == 0) {
        return nil;
    }

    // 移除可能存在的空格
    NSString *cleanedString = [hexString stringByReplacingOccurrencesOfString:@" " withString:@""];

    // 确保字符串长度为偶数
    if (cleanedString.length % 2 != 0) {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithCapacity:cleanedString.length / 2];
    for (NSUInteger i = 0; i < cleanedString.length; i += 2) {
        NSString *byteString = [cleanedString substringWithRange:NSMakeRange(i, 2)];
        NSScanner *scanner = [NSScanner scannerWithString:byteString];

        unsigned int byteValue;
        if (![scanner scanHexInt:&byteValue]) {
            return nil;
        }

        uint8_t byte = (uint8_t)byteValue;
        [data appendBytes:&byte length:1];
    }

    return data;
}

+ (NSString *)hmacSha256:(NSString *)data key:(NSString *)key {
    if (!data || !key) {
        return nil;
    }

    // 将十六进制密钥转换为NSData
    NSData *keyData = [self dataFromHexString:key];
    if (!keyData) {
        return nil;
    }

    // 数据转换
    NSData *dataToSign = [data dataUsingEncoding:NSUTF8StringEncoding];

    // 计算HMAC
    uint8_t digestBytes[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, keyData.bytes, keyData.length, dataToSign.bytes, dataToSign.length, digestBytes);

    // 创建结果数据
    NSData *hmacData = [NSData dataWithBytes:digestBytes length:CC_SHA256_DIGEST_LENGTH];

    // 转换为十六进制字符串
    return [self hexStringFromData:hmacData];
}

+ (NSData *)decryptDataAESCBC:(NSData *)ciphertext
                      withKey:(NSData *)key
                        error:(NSError **)error {
    // 检查输入参数
    if (ciphertext == nil || [ciphertext length] <= kCCBlockSizeAES128 || key == nil || [key length] != kCCKeySizeAES128) {
        if (error) {
            *error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                         code:ALICLOUD_HTTPDNS_ENCRYPT_INVALID_PARAMS_ERROR_CODE
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid input parameters for decryption"}];
        }
        return nil;
    }

    // 提取IV（前16字节）和实际的密文
    NSData *iv = [ciphertext subdataWithRange:NSMakeRange(0, kCCBlockSizeAES128)];
    NSData *actualCiphertext = [ciphertext subdataWithRange:NSMakeRange(kCCBlockSizeAES128, ciphertext.length - kCCBlockSizeAES128)];

    // 计算解密后可能的缓冲区大小
    size_t bufferSize = actualCiphertext.length + kCCBlockSizeAES128;
    size_t decryptedSize = 0;

    // 创建输出缓冲区
    NSMutableData *decryptedData = [NSMutableData dataWithLength:bufferSize];

    // 执行解密
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt,
                                         kCCAlgorithmAES,
                                         kCCOptionPKCS7Padding,
                                         [key bytes],
                                         [key length],
                                         [iv bytes],
                                         [actualCiphertext bytes],
                                         [actualCiphertext length],
                                         [decryptedData mutableBytes],
                                         [decryptedData length],
                                         &decryptedSize);

    if (cryptStatus != kCCSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                         code:ALICLOUD_HTTPDNS_ENCRYPT_FAILED_ERROR_CODE
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Decryption failed with status: %d", cryptStatus]}];
        }
        return nil;
    }

    // 调整解密数据的长度，只保留实际解密内容
    [decryptedData setLength:decryptedSize];

    return decryptedData;
}

@end
