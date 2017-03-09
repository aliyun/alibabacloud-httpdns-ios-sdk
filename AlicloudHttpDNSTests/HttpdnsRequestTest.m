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
#import "AlicloudHttpDNS.h"
#import "HttpdnsRequest.h"
#import "HttpdnsConfig.h"

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
 * 测试目的：测试基于HTTP请求查询功能；
 * 测试方法：1. 查询某个真实域名并判断是否获取了正常的返回数据；
 */
- (void)testHTTPRequestOneHost {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
    NSString *hostName = @"www.taobao.com";
    HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
    NSError *error;
    HttpdnsHostObject *result = [request lookupHostFromServer:hostName error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertNotEqual([[result getIps] count], 0);
}

/**
 * 测试目的：测试基于CFNetwork正确发送HTTPDNS解析请求时，RunLoop是否正确退出；[M]
 * 测试方法：1. [runloop runUtilDate:]后添加日志打印；
 *         2. 并发异步解析几个域名，解析成功后等待并暂停运行，通过查看日志和堆栈信息查看解析线程是否正确退出；
 */
- (void)testSuccessHTTPRequestRunLoop {
    NSArray *array = [NSArray arrayWithObjects:@"www.taobao.com", @"www.baidu.com", @"www.aliyun.com", nil];
    [[HttpDnsService sharedInstance] setPreResolveHosts:array];
    [NSThread sleepForTimeInterval:60];
}

/**
 * 测试目的：测试基于CFNetwork发送HTTPDNS解析请求异常情况时，RunLoop是否正确退出；[M]
 * 测试方法：1. [runloop runUtilDate:]后添加日志打印；
 *         2. 手动更改HTTPDNS IP地址为无效地址(192.192.192.192)；
 *         3. 并发异步解析几个域名，解析后等待并暂停运行，通过查看日志和堆栈信息查看解析线程是否正确退出；
 */
- (void)testFailedHTTPRequestRunLoop {
    NSArray *array = [NSArray arrayWithObjects:@"www.taobao.com", @"www.baidu.com", @"www.aliyun.com", nil];
    [[HttpDnsService sharedInstance] setPreResolveHosts:array];
    [NSThread sleepForTimeInterval:60];
}

/**
 * 测试目的：测试基于CFNetwork发送HTTPDNS解析请求异常情况；[M]
 * 测试方法：并发解析域名请求，模拟网络异常环境，读取数据过程中将网络断开，查看是否出现异常；
 */
- (void)testHTTPRequestException {
    NSArray *array = [NSArray arrayWithObjects:@"www.taobao.com", @"www.baidu.com", @"www.aliyun.com", nil];
    [[HttpDnsService sharedInstance] setPreResolveHosts:array];
    [NSThread sleepForTimeInterval:120];
}

/**
 * 测试目的：测试基于HTTPS请求查询功能；
 * 测试方法：1. 查询某个真实域名并判断是否获取了正常的返回数据；
 */
- (void)testHTTPSRequestOneHost {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
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
 * 测试方法：1. 更改HTTPDNS IP地址为无效地址(192.192.192.192)；2. 查询真实域名并判断是否超时返回，比较超时时间；
 */
- (void)testRequestTimeout {
    NSString *hostName = @"www.baidu.com";
    HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
    NSError *error;
    NSDate *startDate = [NSDate date];
    // HTTP
    startDate = [NSDate date];
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
    [HttpDnsService sharedInstance].timeoutInterval = 5;
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    HttpdnsHostObject *result = [request lookupHostFromServer:hostName error:&error];
    NSTimeInterval interval = [startDate timeIntervalSinceNow];
    XCTAssertEqualWithAccuracy(interval * (-1), customizedTimeoutInterval, 1);
    XCTAssertNotNil(error);
    XCTAssertNil(result);
    
    // HTTPS
    startDate = [NSDate date];
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    result = [request lookupHostFromServer:hostName error:&error];
    interval = [startDate timeIntervalSinceNow];
    
    XCTAssertEqualWithAccuracy(interval * (-1), customizedTimeoutInterval, 1);
    XCTAssertNotNil(error);
    XCTAssertNil(result);
}


@end
