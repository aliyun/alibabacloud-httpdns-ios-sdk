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

#import <XCTest/XCTest.h>
#import "Httpdns.h"
#import "HttpdnsUtil.h"

@interface HttpdnsUtilTest : XCTestCase

@end

@implementation HttpdnsUtilTest

+ (void)initialize {
    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
    [httpdns setLogEnabled:YES];
    [httpdns setAccountID:100000];
}

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

/**
 * 测试目的：测试上报逻辑；[M]
 * 测试方法：初始化看是否上报，后发起请求看是否重复上报；
 */
- (void)testStat {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5.0]];
    NSString *hostName = @"www.taobao.com";
    [[HttpDnsService sharedInstance] getIpByHost:hostName];
}


/**
 * 测试目的：测试IP判断接口功能；
 * 测试方法：1. 给出多个合法/非法IP，测试返回情况；
 */
- (void)testCheckIfIsAnIp {
    NSString *s1 = @"12.23.3.44";
    NSString *s2 = @"www.taobao.com";
    NSString *s3 = @"234.1444.22.33";
    NSString *s4 = @"257.1.1.1";
    NSString *s5 = @"0.0.0.0";
    NSString *s6 = @"0000";
    XCTAssertTrue([HttpdnsUtil isAnIP:s1]);
    XCTAssertFalse([HttpdnsUtil isAnIP:s2]);
    XCTAssertFalse([HttpdnsUtil isAnIP:s3]);
    XCTAssertFalse([HttpdnsUtil isAnIP:s4]);
    XCTAssertTrue([HttpdnsUtil isAnIP:s5]);
    XCTAssertFalse([HttpdnsUtil isAnIP:s6]);
}


/**
 * 测试目的：测试host合法判断功能；
 * 测试方法：1. 给出多个用例，判断是否能正确测试出是否为host；
 */
-(void)testHostLegalJudge{
    NSString *host1 = @"nihao";
    NSString *host2 = @"baidu.com";
    NSString *host3 = @"https://www.baidu.com/";
    NSString *host4 = @"zhihu.com";
    NSString *host5 = @"123123/32,daf";
    XCTAssertEqual([HttpdnsUtil isAHost:host1], YES);
    XCTAssertEqual([HttpdnsUtil isAHost:host2], YES);
    XCTAssertEqual([HttpdnsUtil isAHost:host3], NO);
    XCTAssertEqual([HttpdnsUtil isAHost:host4], YES);
    XCTAssertEqual([HttpdnsUtil isAHost:host5], NO);
}

@end
