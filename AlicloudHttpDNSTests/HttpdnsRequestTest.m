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
#import "HttpdnsRequest.h"

@interface HttpdnsRequestTest : XCTestCase

@end

@implementation HttpdnsRequestTest

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
 * 测试目的：测试查询功能；
 * 测试方法：1. 查询某个真实域名并判断是否获取了正常的返回数据；
 */
- (void)testRequestOneHost {
    NSString *hostName = @"www.taobao.com";
    HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
    NSError *error;
    HttpdnsHostObject *result = [request lookupHostFromServer:hostName error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertNotEqual([[result getIps] count], 0);
}

/**
 * 测试目的：测试查询超时；[M]
 * 测试方法：1. 更改HTTPDNS IP地址为无效地址；2. 查询真实域名并判断是否超时返回；
 */
//- (void)testRequestTimeout {
//    NSString *hostName = @"www.baidu.com";
//    HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
//    NSError *error;
//    HttpdnsHostObject *result = [request lookupHostFromServer:hostName error:&error];
//    XCTAssertNotNil(error);
//    XCTAssertNil(result);
//}


@end