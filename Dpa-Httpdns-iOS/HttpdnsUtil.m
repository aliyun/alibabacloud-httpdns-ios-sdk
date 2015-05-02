//
//  HttpdnsUtil.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsUtil.h"
#import "CommonCrypto/CommonCrypto.h"

@implementation HttpdnsUtil

+(NSString *)HMACSha1Sign:(NSData *)data withKey:(NSString *)key {
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
@end
