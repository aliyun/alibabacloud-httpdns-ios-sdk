//
//  HttpdnsUtilTest.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/3/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "HttpdnsUtil.h"

@interface HttpdnsUtilTest : XCTestCase

@end

@implementation HttpdnsUtilTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testBase64Sha1SignAlgorithem {
    NSString *sk = @"hello";
    NSString *appid = @"123456";
    NSString *host=@"www.taobao.com,mcgw.alipay.com";
    NSString *timestamp = @"1430164514";
    NSString *version = @"1";
    NSString *contentToSign = [NSString stringWithFormat:@"%@%@%@%@", version, appid, timestamp, host];
    NSData *dataToSign = [contentToSign dataUsingEncoding:NSUTF8StringEncoding];
    NSString *sign = [HttpdnsUtil HMACSha1Sign:dataToSign withKey:sk];
    NSLog(@"signature: %@", sign);
    XCTAssertEqual([sign isEqualToString:@"Tt8VgdCSMewCAmFqm76tSmRAJu4="], YES, @"is equal");
}

@end
