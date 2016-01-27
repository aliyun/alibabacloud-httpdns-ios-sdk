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
#import "HttpdnsModel.h"

@interface HttpdnsLocalCacheTest : XCTestCase

@end

@implementation HttpdnsLocalCacheTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    [HttpdnsLog enableLog];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}


/**
 * 测试目的：缓存模块读写功能
 * 测试方法：1. 设置一个自定义对象，写入缓存；2. 读取缓存，判断是否是写入的对象；
 */
- (void)testReadAndWriteNormally {
    HttpdnsIpObject *ip = [[HttpdnsIpObject alloc] init];
    [ip setIp:@"223.5.5.5"];
    HttpdnsHostObject *host = [[HttpdnsHostObject alloc] init];
    [host setHostName:@"www.taobao.com"];
    NSArray *ipArray = [[NSArray alloc] initWithObjects:ip, nil];
    [host setIps:ipArray];
    NSMutableDictionary *testDict = [[NSMutableDictionary alloc] init];
    [testDict setObject:host forKey:@"test-host"];
    sleep(60);
    [HttpdnsLocalCache writeToLocalCache:testDict];
    NSDictionary *dict = [HttpdnsLocalCache readFromLocalCache];
    XCTAssertEqual(1, [dict count]);
    HttpdnsHostObject *hostObject = [dict objectForKey:@"test-host"];
    XCTAssertEqualObjects(@"223.5.5.5", [[[hostObject getIps] objectAtIndex:0] getIpString]);
    XCTAssertEqualObjects(@"www.taobao.com", [hostObject getHostName]);
}

/**
 * 测试目的：缓存模块清除功能
 * 测试方法：1. 设置一个自定义对象，写入缓存；2. 读取缓存，判断是否是写入的对象；3. 清除缓存； 4. 再次读取，判断是否还能读出数据；
 */
- (void)testCleanCache {
    HttpdnsIpObject *ip = [[HttpdnsIpObject alloc] init];
    [ip setIp:@"223.5.5.5"];
    HttpdnsHostObject *host = [[HttpdnsHostObject alloc] init];
    [host setHostName:@"www.taobao.com"];
    NSArray *ipArray = [[NSArray alloc] initWithObjects:ip, nil];
    [host setIps:ipArray];
    NSMutableDictionary *testDict = [[NSMutableDictionary alloc] init];
    [testDict setObject:host forKey:@"test-host"];
    sleep(60);
    [HttpdnsLocalCache writeToLocalCache:testDict];
    NSDictionary *dict = [HttpdnsLocalCache readFromLocalCache];
    XCTAssertEqual(1, [dict count]);
    HttpdnsHostObject *hostObject = [dict objectForKey:@"test-host"];
    XCTAssertEqualObjects(@"223.5.5.5", [[[hostObject getIps] objectAtIndex:0] getIpString]);
    XCTAssertEqualObjects(@"www.taobao.com", [hostObject getHostName]);
    [HttpdnsLocalCache cleanLocalCache];
    sleep(30);
    dict = [HttpdnsLocalCache readFromLocalCache];
    XCTAssertEqualObjects(nil, dict);
}


@end
