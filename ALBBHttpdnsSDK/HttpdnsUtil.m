//
//  HttpdnsUtil.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"
#import "CommonCrypto/CommonCrypto.h"
#import "arpa/inet.h"

@implementation HttpdnsUtil

+(NSString *)Base64HMACSha1Sign:(NSData *)data withKey:(NSString *)key {
    CCHmacContext context;
    const char    *keyCString = [key cStringUsingEncoding:NSASCIIStringEncoding];

    CCHmacInit(&context, kCCHmacAlgSHA1, keyCString, strlen(keyCString));
    CCHmacUpdate(&context, [data bytes], [data length]);

    unsigned char digestRaw[CC_SHA256_DIGEST_LENGTH];
    NSInteger digestLength = CC_SHA1_DIGEST_LENGTH;

    CCHmacFinal(&context, digestRaw);
    NSData *digestData = [NSData dataWithBytes:digestRaw length:digestLength];

    return [digestData base64EncodedStringWithOptions:kNilOptions];
}

+(long long)currentEpochTimeInSecond {
    return (long long)[[[NSDate alloc] init] timeIntervalSince1970];
}

+(NSString *)currentEpochTimeInSecondString {
    return [NSString stringWithFormat:@"%lld", [HttpdnsUtil currentEpochTimeInSecond]];
}

+(BOOL)checkIfIsAnIp:(NSString *)candidate {
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
+(BOOL)checkIfIsAnHost:(NSString *)host {
    static NSRegularExpression *hostExpression = nil ;
    
    if (hostExpression == nil) {
        hostExpression = [[NSRegularExpression alloc] initWithPattern:@"^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$" options:NSRegularExpressionCaseInsensitive error:nil];
    }

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
@end
