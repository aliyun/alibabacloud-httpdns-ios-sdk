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
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsRequestScheduler_Internal.h"

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
    [HttpdnsRequestScheduler configureServerIPsAndResetActivatedIPTime];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    sleep(customizedTimeoutInterval);
    [super tearDown];
}

/**
 * 测试目的：测试基于HTTP请求查询功能；
 * 测试方法：1. 查询某个真实域名并判断是否获取了正常的返回数据；
 */
- (void)testHTTPRequestOneHost {
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
 * 测试目的：测试基于CFNetwork正确发送HTTPDNS解析请求时，RunLoop是否正确退出；[M]
 * 测试方法：1. [runloop runUtilDate:]后添加日志打印；
 *         2. 并发异步解析几个域名，解析成功后等待并暂停运行，通过查看日志和堆栈信息查看解析线程是否正确退出；
 */
- (void)testSuccessHTTPRequestRunLoop {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];

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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];

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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    [HttpDnsService sharedInstance].timeoutInterval = 3;
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    HttpdnsHostObject *result = [request lookupHostFromServer:hostName error:&error];
    NSTimeInterval interval = [startDate timeIntervalSinceNow];
    XCTAssert(interval <= customizedTimeoutInterval);
    XCTAssertNil(error);
    XCTAssertNil(result);
    
    // HTTPS
    startDate = [NSDate date];
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    result = [request lookupHostFromServer:hostName error:&error];
    interval = [startDate timeIntervalSinceNow];
    
    XCTAssert(interval <= customizedTimeoutInterval);
    XCTAssertNil(error);
    XCTAssertNil(result);
}

//https://aone.alibaba-inc.com/req/10610013

#pragma mark - Disable and Sniffer Test
///=============================================================================
/// @name Disable and Sniffer Test
///=============================================================================


#pragma mark -
#pragma mark - 业务永续方案测试用例


/*!
 * IP轮转机制功能验证1
 测试目的：IP轮转机制是否可以正常运行
 测试方法：
 将IP轮转池中的第一个ip设置为无效ip，将ip轮转重置时间设置为t
 调用域名解析接口解析域名A，查看日志，是否ip_1解析超时异常，ip_2解析正常
 调用域名解析接口解析域名B，查看日志，是否使用ip_2进行解析
 重启App，调用域名解析接口解析域名C，查看日志，是否使用ip_2进行解析
 等待t
 重启App，调用域名解析接口解析域名，查看日志是否使用ip_1进行解析
 */
- (void)testIPPool {
    NSString *hostName = @"www.taobao.com";
    HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
    HttpdnsRequestScheduler *requestScheduler =  [[HttpDnsService sharedInstance] requestScheduler];
    
    requestScheduler.activatedServerIPIndex = 0;
    [requestScheduler.testHelper setFirstIPWrongForTest];
    NSError *error;
    NSDate *startDate = [NSDate date];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    HttpdnsHostObject *result = [request lookupHostFromServer:hostName error:&error];
    NSTimeInterval interval = [startDate timeIntervalSinceNow];
    XCTAssertEqualWithAccuracy(interval * (-1), customizedTimeoutInterval, 1);
    
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual([[result getIps] count], 0);
    
    startDate = [NSDate date];
    result = [request lookupHostFromServer:hostName error:&error];
    interval = [startDate timeIntervalSinceNow];
    XCTAssert(-interval < customizedTimeoutInterval);
    
    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertNotEqual([[result getIps] count], 0);
    [HttpdnsRequestScheduler configureServerIPsAndResetActivatedIPTime];
}

/*!
 *
 测试目的：测试IP池子轮转是否可以循环
 测试方法：
 将IP轮转池大小设置为3，且全部为无效ip
 调用域名解析接口解析域名A， 查看日志：1）是否分别使用ip_1,ip_2各解析一次，且两次均超时；2）是否使用ip_3发起主动嗅探，超时一次
 等待30S
 调用解析接口解析域名，查看日志：1）是否使用ip_1进行解析；2）请求超时一次
 */
- (void)testIPPoolLoop {
    [self testIPPoolLoopWithHTTPS:NO];
}

- (void)testIPPoolLoopWithHTTPS {
    [self testIPPoolLoopWithHTTPS:YES];
}

- (void)testIPPoolLoopWithHTTPS:(BOOL)isHTTPS {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:isHTTPS];
    
    NSString *hostName = @"www.taobao.com";
    HttpdnsRequestScheduler *requestScheduler =  [[HttpDnsService sharedInstance] requestScheduler];
    [requestScheduler setServerDisable:NO host:hostName];
    
    requestScheduler.activatedServerIPIndex = 0;
    
    [requestScheduler.testHelper setTwoFirstIPWrongForTest];
    [requestScheduler.testHelper zeroSnifferTimeForTest];

    NSDate *startDate = [NSDate date];
    XCTAssert(![requestScheduler isServerDisable]);
    [[HttpDnsService sharedInstance] getIpByHost:hostName];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    NSTimeInterval interval = [startDate timeIntervalSinceNow];
    sleep(0.02);//嗅探前
    XCTAssert([requestScheduler isServerDisable]);

    XCTAssert(-interval >= 2* customizedTimeoutInterval);
    XCTAssert(-interval < 3* customizedTimeoutInterval);
    
    //嗅探中
    sleep(customizedTimeoutInterval);
    XCTAssertEqual(requestScheduler.activatedServerIPIndex, 2);

    //重试2次
    XCTAssert(![requestScheduler isServerDisable]);
    
    [HttpdnsRequestScheduler configureServerIPsAndResetActivatedIPTime];
}

/*!
 disable降级机制功能验证
 */
- (void)testDisable {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    [HttpDnsService sharedInstance].timeoutInterval = 5;
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO host:hostName];
    requestScheduler.activatedServerIPIndex = 0;
    
    [requestScheduler.testHelper setFourFirstIPWrongForTest];
    [requestScheduler.testHelper zeroSnifferTimeForTest];
    [service getIpByHost:hostName];
    
    //重试2次+嗅探1次
    sleep(customizedTimeoutInterval + 1);
    XCTAssert([requestScheduler isServerDisable]);
    
    //第2次嗅探失败
    [service getIpByHost:hostName];
    XCTAssert([requestScheduler isServerDisable]);
    sleep(customizedTimeoutInterval + 1);
    
    //第3次嗅探成功
    [service getIpByHost:hostName];
    sleep(customizedTimeoutInterval + 1);
    sleep(1);//正在异步更新isServerDisable状态
    
    //第3次嗅探成功
    [service getIpByHost:hostName];
    sleep(customizedTimeoutInterval + 1);
    
    XCTAssert(![requestScheduler isServerDisable]);
    [HttpdnsRequestScheduler configureServerIPsAndResetActivatedIPTime];
}

/*!
 * 并发访问相同的错误IP，activatedServerIPIndex应该是唯一的，应该是错误IP的下一个。
 */
- (void)testComplicatedlyAccessSameWrongHostIP {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO host:hostName];
    requestScheduler.activatedServerIPIndex = 0;
    
    [requestScheduler.testHelper setFirstIPWrongForTest];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;

    dispatch_queue_t concurrentQueue =
    dispatch_queue_create("com.ConcurrentQueue",
                          DISPATCH_QUEUE_CONCURRENT);
    for (int i = 0; i < 5; i++) {
        dispatch_async(concurrentQueue, ^{
            [service getIpByHost:hostName];
        });
    }
    dispatch_barrier_sync(concurrentQueue, ^{
        sleep(customizedTimeoutInterval);
        XCTAssert(![requestScheduler isServerDisable]);
        XCTAssertEqual(requestScheduler.activatedServerIPIndex, 1);
    });

}

/*!
 * 并发嗅探，结果一致，不会导致叠加
 */
- (void)testComplicatedlyAccessSameTwoWrongHostIP {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO host:hostName];
    requestScheduler.activatedServerIPIndex = 0;
    
    [requestScheduler.testHelper setTwoFirstIPWrongForTest];
    [requestScheduler.testHelper zeroSnifferTimeForTest];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    
    dispatch_queue_t concurrentQueue =
    dispatch_queue_create("com.ConcurrentQueue",
                          DISPATCH_QUEUE_CONCURRENT);
    for (int i = 0; i < 5; i++) {
        dispatch_async(concurrentQueue, ^{
            [service getIpByHost:hostName];
        });
    }
    dispatch_barrier_sync(concurrentQueue, ^{
        sleep(customizedTimeoutInterval);
        XCTAssert(![requestScheduler isServerDisable]);
        XCTAssertEqual(requestScheduler.activatedServerIPIndex, 2);
    });
}
/*!
 * 最初的IP index非0的情况下，并发访问
 
 0 wrong
 1 wrong <--start IP
 2 wrong
 3 wrong
 4 right
 */
- (void)testComplicatedlyAccessSameFourWrongHostIP {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO host:hostName];
    requestScheduler.activatedServerIPIndex = 1;
    [requestScheduler.testHelper zeroSnifferTimeForTest];
    
    [requestScheduler.testHelper setFourFirstIPWrongForTest];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    
    dispatch_queue_t concurrentQueue =
    dispatch_queue_create("com.ConcurrentQueue",
                          DISPATCH_QUEUE_CONCURRENT);
    for (int i = 0; i < 5; i++) {
        dispatch_async(concurrentQueue, ^{
            [service getIpByHost:hostName];
            sleep(customizedTimeoutInterval);
            [service getIpByHost:hostName];
        });
    }
    dispatch_barrier_sync(concurrentQueue, ^{
        sleep(customizedTimeoutInterval);
        XCTAssert(![requestScheduler isServerDisable]);
        XCTAssertEqual(requestScheduler.activatedServerIPIndex, 4);
    });
}

/*!
 * 
 嗅探间隔是否生效
 最初的IP index非0的情况下，并发访问
 
 0 wrong
 1 wrong <--start IP
 2 wrong
 3 wrong
 4 right
 */
- (void)testComplicatedlyAccessSameFourWrongHostIPWithDisableStatus {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO host:hostName];
    requestScheduler.activatedServerIPIndex = 1;
    
    [requestScheduler.testHelper setFourFirstIPWrongForTest];
//    [requestScheduler.testHelper zeroSnifferTimeForTest];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    
    dispatch_queue_t concurrentQueue =
    dispatch_queue_create("com.ConcurrentQueue",
                          DISPATCH_QUEUE_CONCURRENT);
    for (int i = 0; i < 5; i++) {
        dispatch_async(concurrentQueue, ^{
            [service getIpByHost:hostName];
            sleep(customizedTimeoutInterval);
            [service getIpByHost:hostName];
        });
    }
    dispatch_barrier_sync(concurrentQueue, ^{
        sleep(customizedTimeoutInterval);
        XCTAssert([requestScheduler isServerDisable]);
        XCTAssertEqual(requestScheduler.activatedServerIPIndex, 3);
        XCTAssertNil([service getIpByHost:hostName]);
    });
}

@end
