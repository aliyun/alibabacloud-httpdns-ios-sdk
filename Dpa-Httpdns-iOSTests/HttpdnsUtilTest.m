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

- (void)testBase64Sha1SignAlgorithm {
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

- (void)testCheckIfIsAnIp {
    NSString *s1 = @"12.23.3.44";
    NSString *s2 = @"www.taobao.com";
    NSString *s3 = @"234.1444.22.33";
    NSString *s4 = @"257.1.1.1";
    NSString *s5 = @"0.0.0.0";
    NSString *s6 = @"0000";
    XCTAssertTrue([HttpdnsUtil checkIfIsAnIp:s1], "failed");
    XCTAssertFalse([HttpdnsUtil checkIfIsAnIp:s2], "failed");
    XCTAssertFalse([HttpdnsUtil checkIfIsAnIp:s3], "failed");
    XCTAssertFalse([HttpdnsUtil checkIfIsAnIp:s4], "failed");
    XCTAssertTrue([HttpdnsUtil checkIfIsAnIp:s5], "failed");
    XCTAssertFalse([HttpdnsUtil checkIfIsAnIp:s6], "failed");
}
@end
