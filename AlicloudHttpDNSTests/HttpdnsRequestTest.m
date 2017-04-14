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
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsScheduleCenter_Internal.h"
#import "TestBase.h"

//#import "RequestSchedulerTestHelper.h"
#import "ScheduleCenterTestHelper.h"

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
//    [ScheduleCenterTestHelper resetAutoConnectToScheduleCenter];
    [ScheduleCenterTestHelper resetAllThreeRightForTest];
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
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    sleep(customizedTimeoutInterval);
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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
    NSArray *array = [NSArray arrayWithObjects:@"www.taobao.com", @"www.baidu.com", @"www.aliyun.com", nil];
    [[HttpDnsService sharedInstance] setPreResolveHosts:array];
    [NSThread sleepForTimeInterval:60];
}

- (void)testSuccessHTTPSRequestRunLoop0 {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    NSArray *array = [NSArray arrayWithObjects:@"www.taobao.com", @"www.baidu.com", @"www.aliyun.com", nil];
    [[HttpDnsService sharedInstance] setPreResolveHosts:array];
    [NSThread sleepForTimeInterval:60];
}

- (void)testSuccessHTTPSRequestRunLoop1 {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:YES];
    NSArray *array = [NSArray arrayWithObjects:@"www.taobao.com", @"www.baidu.com", @"www.aliyun.com", nil];
    [[HttpDnsService sharedInstance] setPreResolveHosts:array];
    [NSThread sleepForTimeInterval:60];
}

- (void)testSuccessHTTPSRequestRunLoop2 {
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
//    HttpdnsRequestScheduler *requestScheduler =  [[HttpDnsService sharedInstance] requestScheduler];
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 0;
    [ScheduleCenterTestHelper setFirstIPWrongForTest];
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
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 0;
    
    [ScheduleCenterTestHelper setTwoFirstIPWrongForTest];
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];

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
    XCTAssertEqual(scheduleCenter.activatedServerIPIndex, 2);

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
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 0;
    
    [ScheduleCenterTestHelper setFourFirstIPWrongForTest];
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];
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
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 0;
    
    [ScheduleCenterTestHelper setFirstIPWrongForTest];
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
        XCTAssertEqual(scheduleCenter.activatedServerIPIndex, 1);
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
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];

    scheduleCenter.activatedServerIPIndex = 0;
    
<<<<<<< HEAD
    [requestScheduler.testHelper setTwoFirstIPWrongForTest];
    [requestScheduler.testHelper zeroSnifferTimeForTest];
=======
    [ScheduleCenterTestHelper setTwoFirstIPWrongForTest];
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];

>>>>>>> v6 version
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
        XCTAssertEqual(scheduleCenter.activatedServerIPIndex, 2);
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
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 1;
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];
    
    [ScheduleCenterTestHelper setFourFirstIPWrongForTest];
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
        XCTAssertEqual(scheduleCenter.activatedServerIPIndex, 4);
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
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 1;
    
    [ScheduleCenterTestHelper setFourFirstIPWrongForTest];
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
        XCTAssertEqual(scheduleCenter.activatedServerIPIndex, 3);
        XCTAssertNil([service getIpByHost:hostName]);
    });
}

/*!
 * 最初的IP index非0的情况下，并发访问
 
 0 right
 1 wrong <--start IP
 2 wrong
 3 wrong
 4 wrong
 */
- (void)testComplicatedlyAccessSameLastFourWrongHostIP {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
    
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO host:hostName];
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 1;
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];
    
    [ScheduleCenterTestHelper setFourLastIPWrongForTest];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    
    dispatch_queue_t concurrentQueue =
    dispatch_queue_create("com.ConcurrentQueue",
                          DISPATCH_QUEUE_CONCURRENT);
    for (int i = 0; i < 5; i++) {
        dispatch_async(concurrentQueue, ^{
            //三次 = 两次重试 + 一次嗅探
            [service getIpByHost:hostName];
            sleep(customizedTimeoutInterval);
            
            //嗅探
            [service getIpByHost:hostName];
            sleep(customizedTimeoutInterval);
            
        });
    }
    dispatch_barrier_sync(concurrentQueue, ^{
        XCTAssert([requestScheduler isServerDisable]);
        
        //嗅探正确的IP，但先返回nil。
        XCTAssertNil([service getIpByHost:hostName]);
        sleep(customizedTimeoutInterval);

        //已经切到正确的IP
        XCTAssert(![requestScheduler isServerDisable]);
        XCTAssertNotNil([service getIpByHost:hostName]);
        XCTAssertEqual(scheduleCenter.activatedServerIPIndex, 0);
    });
}

/**
 * 测试目的：测试 ScheduleCenter 的触发条件：IP全部超时，会触发。
 * 测试方法：将现有的所有IP置为错误的IP，尝试触发SC，之后再发请求，如果成功即通过。
 * 详细步骤：
 *          1. 将当前server ip列表全部置换为错误ip
 *          2. 解析域名，查看日志：1)分别使用ip1，ip2，ip3进行解析，均失败，
 *          3. 等待30S，解析域名，查看日志：1）用ip4发起一次嗅探，失败
 *          4. 等待30S，解析域名，查看日志：1)用ip5发起嗅探，失败，触发 ScheduleCenter 更新
 *          5. 解析域名，查看日志：1）通过更新后的ip进行解析； 2)成功解析，disable状态解除
 */
- (void)testScheduleCenterTrigger {
    [ScheduleCenterTestHelper cancelAutoConnectToScheduleCenter];
    [ScheduleCenterTestHelper setAllThreeWrongForTest];

    HttpDnsService *service = [HttpDnsService sharedInstance];
    NSString *hostName = @"www.taobao.com";
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO host:hostName];
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 0;
    
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];
    [HttpdnsScheduleCenterTestHelper zeroMixConnectToScheduleCenterInterval];
    [HttpdnsScheduleCenterTestHelper zeroAutoConnectToScheduleCenterInterval];
    [service getIpByHost:hostName];

}

/**
 * 测试目的：测试 ScheduleCenter 是否可以正常更新server ip
 * 测试方法：取内置默认的 IP 列表的首个 IP，手动调用SC请求，再取首个 IP，看能否是对应。并看本地文件的更新时间戳。
 */
- (void)testScheduleCenterUpdateIPList {
    [ScheduleCenterTestHelper setAllThreeWrongForTest];
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    [HttpdnsScheduleCenterTestHelper zeroMixConnectToScheduleCenterInterval];
    [HttpdnsScheduleCenterTestHelper zeroAutoConnectToScheduleCenterInterval];
    [scheduleCenter forceUpdateIpListAsync];
    NSTimeInterval timeInterval = 15 * 2;
    sleep(timeInterval);
    //SC更新本地文件的时间戳
    NSTimeInterval time = [ScheduleCenterTestHelper timeSinceCreateForScheduleCenterResult];
    NSLog(@"%@", @(time));
    XCTAssertTrue(time < timeInterval + 1);
    XCTAssertTrue(time >= 0);
    {
    NSTimeInterval time = [ScheduleCenterTestHelper timeSinceCreateForScheduleCenterResult];
        NSLog(@"%@", @(time));
    }
    XCTAssertTrue(![scheduleCenter.IPList[0] isEqualToString:@"190.190.190.190"]);
    XCTAssertTrue([scheduleCenter.IPList[0] isEqualToString:@"203.107.1.65"]);
}

/**
 *  测试目的：测试 ScheduleCenter 的停服操作是否能够生效，
 *  测试步骤：控制 ScheduleCenter 返回的值为停服，然后使用任意 API 看是否始终返回nil。
 */
- (void)testScheduleCenterStopService {
    [ScheduleCenterTestHelper cancelAutoConnectToScheduleCenter];
    [ScheduleCenterTestHelper setStopService];
    NSString *hostName = @"www.taobao.com";
        HttpDnsService *service = [HttpDnsService sharedInstance];
        XCTAssertNil([service getIpByHost:hostName]);
    sleep(10);
    XCTAssertNil([service getIpByHost:hostName]);
    sleep(10);
    XCTAssertNil([service getIpByHost:hostName]);
    [ScheduleCenterTestHelper resetAllThreeRightForTest];
}

/**
 * 测试目的：测试 ScheduleCenter 24小时内，持久化功能是否正常 以及测试 ScheduleCenter 的触发条件：每24小时的间隔，触发一次。最小时间间隔为5MIN。
 *        （三个IP失败后就继续按照原来的 IP 池轮转。如果IP池再轮转了一遍且继续失败重新触发SC时必须距上一次SC5min以上才会真正发起新的SC）
 * 测试方法：修改24小时，为较短时间比如10秒，5MIN 为 5S，
 *           1. 测试5MIN间隔：为手动调用 SC 请求，sleep 4秒，再请求，不能请求。再sleep 1秒，再请求，可以请求。
 *           2. 测试24小时内只主动请求一次：设置24小时为较短时间，比如10S，首次启动后，会更新 IP 列表。10S内再次启动不会更新IP列表，10S后再次启动会更新列表。
 *           3. 请求成功与否判断：本地是否能更新。获取本地固化数据的最近更新时间。
 */
- (void)testScheduleCenterInterval {
//    [ScheduleCenterTestHelper cancelAutoConnectToScheduleCenter];

    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    [HttpdnsScheduleCenterTestHelper shortMixConnectToScheduleCenterInterval];
    [HttpdnsScheduleCenterTestHelper shortAutoConnectToScheduleCenterInterval];
    __block NSTimeInterval timeInterval1 = 0;
    __block NSTimeInterval timeInterval2 = 0;
    __block NSTimeInterval timeInterval3 = 0;
//    sleep(10);
    //超过最小间隔，可以更新。误差为1妙
    NSTimeInterval sleepTime = 1;
    [scheduleCenter forceUpdateIpListAsyncWithCallback:^(NSDictionary *result) {
        sleep(sleepTime);
        timeInterval1 = [ScheduleCenterTestHelper timeSinceCreateForScheduleCenterResult];
        XCTAssertNotNil(result);
        XCTAssertTrue(timeInterval1 < sleepTime + 1);
        NOTIFY
    }];
    WAIT
    //未超过最小间隔，不可以更新

    [scheduleCenter forceUpdateIpListAsyncWithCallback:^(NSDictionary *result) {
        sleep(sleepTime);
        timeInterval2 = [ScheduleCenterTestHelper timeSinceCreateForScheduleCenterResult];
        XCTAssertNil(result);
        NOTIFY
    }];
    WAIT
    sleep(5);
    //超过最小间隔，可以更新
    [scheduleCenter forceUpdateIpListAsyncWithCallback:^(NSDictionary *result) {
        sleep(sleepTime);
        XCTAssertNotNil(result);
        XCTAssertTrue(timeInterval3<sleepTime+1);
        timeInterval3 = [ScheduleCenterTestHelper timeSinceCreateForScheduleCenterResult];
        XCTAssertTrue(timeInterval2 > timeInterval1 + sleepTime);
        XCTAssertTrue(timeInterval2 < timeInterval1 + sleepTime + 1);
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@==%@==%@", @(__PRETTY_FUNCTION__), @(__LINE__), @(timeInterval1), @(timeInterval2), @(timeInterval3));
        NOTIFY
    }];
    WAIT
}

/**
 * 测试目的：SC 触发失败后，测试SC的轮转机制。
 * 测试方法：
 *          1. 将 server ips 大小设置为3，且均为错误ip。同时将 ScheduleCenter 访问 ip 全部设置为错误 ip。
 *          2. 解析域名,观察日志：1) 三次尝试均失败；2) 访问 ScheduleCenter ，且三次尝试均失败。查看SC轮转的IP的index。
 *          3. 解析域名,观察日志： 1) 处于 disable 模式,准备启动嗅探； 2) 访问 ScheduleCenter 未完成,放弃嗅探。
 *          4. 解析域名,观察日志：1) 发起一次嗅探，且继续按照原有 IP 轮转逻辑进行访问。
 */
- (void)testScheduleCenterRetry {
    [ScheduleCenterTestHelper cancelAutoConnectToScheduleCenter];
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    [HttpdnsScheduleCenterTestHelper shortMixConnectToScheduleCenterInterval];
    [HttpdnsScheduleCenterTestHelper shortAutoConnectToScheduleCenterInterval];
    //超过最小间隔，可以更新。位差为1妙
    NSTimeInterval sleepTime = 0.3;
    [HttpdnsScheduleCenterTestHelper setFirstTwoWrongForScheduleCenterIPs];
    [scheduleCenter forceUpdateIpListAsyncWithCallback:^(NSDictionary *result) {
        sleep(sleepTime);
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), result);
        XCTAssertNotNil(result);
        NOTIFY
    }];
    WAIT
}

/**
 * 测试目的：用户 Level 变更后，服务端返回403错误，也会触发SC。
 * 测试方法：访问测试服务器，始终返回403，看能否最终更新本地 IP 列表，并访问成功。
 *http://30.27.80.142:3000/httpdns403/100000/d?host=www.taobao.com   mock403错误
 *http://30.27.80.142:3000/sc/httpdns_config?account_id=153519&platform=android&sdk_version=1.2.4
   mock disable错误 可以用这个来测试sc disable状态和降级错误
 */
- (void)testScheduleCenterUserLevelChanged {
    [ScheduleCenterTestHelper cancelAutoConnectToScheduleCenter];
    [ScheduleCenterTestHelper setAllThreeWrongForTest];
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    XCTAssertNil([service getIpByHost:hostName]);

        HttpdnsRequestScheduler *requestScheduler =  [[HttpDnsService sharedInstance] requestScheduler];

    NSInteger code = 403;
    NSDictionary *errorInfo = @{
                                @"ErrorMessage" : @"ServiceLevelDeny",
                                  };
    NSError *error = [NSError errorWithDomain:NSStringFromClass([self class])
                                         code:code
                                     userInfo:errorInfo];
    
    [requestScheduler canNotResolveHost:hostName error:error isRetry:NO activatedServerIPIndex:0];
    sleep(20);
    XCTAssertNotNil([service getIpByHost:hostName]);

}

@end
