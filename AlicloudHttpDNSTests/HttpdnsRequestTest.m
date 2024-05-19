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
#import "HttpdnsService_Internal.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsScheduleCenter_Internal.h"
#import "TestBase.h"
#import "HttpdnsConstants.h"

//#import "RequestSchedulerTestHelper.h"
#import "ScheduleCenterTestHelper.h"
#import "HttpdnsHostCacheStore.h"
#import "HttpdnsIPCacheStore.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsIPRecord.h"
#import "HttpdnsHostCacheStore_Internal.h"

@interface HttpdnsRequestTest : XCTestCase

@end

@implementation HttpdnsRequestTest

+ (void)initialize {
//    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
//    [httpdns setLogEnabled:YES];
//    [httpdns setAccountID:100000];

//    HttpDnsService *httpdns = [[HttpDnsService alloc] initWithAccountID:100000];
    HttpDnsService *httpdns = [[HttpDnsService alloc] initWithAccountID:191863];
    [httpdns setLogEnabled:YES];
    NSDictionary *IPRankingDatasource = @{
                                          @"www.aliyun.com" : @80,
                                          @"www.taobao.com" : @80,
                                          @"gw.alicdn.com" : @443,
                                          @"www.tmall.com" : @443,
                                          @"dou.bz" : @443
                                          };
//    [httpdns setPreResolveHosts:preResolveHosts];
    [httpdns setIPRankingDatasource:IPRankingDatasource];
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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
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

- (void)testRequestRunloopCreate {
    for (int i = 0; i < 300 ; i++) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
            NSString *hostName = @"www.taobao.com";
            HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
            NSError *error;
            HttpdnsHostObject *result = [request lookupHostFromServer:hostName error:&error];
            XCTAssertNil(error);
            XCTAssertNotNil(result);
            XCTAssertNotEqual([[result getIps] count], 0);
        });
    }
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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
    NSArray *array = [NSArray arrayWithObjects:@"www.taobao.com", @"www.baidu.com", @"www.aliyun.com", nil];
    [[HttpDnsService sharedInstance] setPreResolveHosts:array];
    [NSThread sleepForTimeInterval:60];
}

- (void)testSuccessHTTPSRequestRunLoop1 {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
    NSArray *array = [NSArray arrayWithObjects:@"www.taobao.com", @"www.baidu.com", @"www.aliyun.com", nil];
    [[HttpDnsService sharedInstance] setPreResolveHosts:array];
    [NSThread sleepForTimeInterval:60];
}

- (void)testSuccessHTTPSRequestRunLoop2 {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];

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
//    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
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
    [HttpDnsService sharedInstance].timeoutInterval = 3;
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    HttpdnsHostObject *result = [request lookupHostFromServer:hostName error:&error];
    NSTimeInterval interval = [startDate timeIntervalSinceNow];
    XCTAssert(interval <= customizedTimeoutInterval);
    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), error);
    //与帐号是否添加baidu.com有关
//    XCTAssertNil(result);

    // HTTPS
    startDate = [NSDate date];
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
    result = [request lookupHostFromServer:hostName error:&error];
    interval = [startDate timeIntervalSinceNow];

    XCTAssert(interval <= customizedTimeoutInterval);
    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), error);
    //与帐号是否添加baidu.com有关
//    XCTAssertNil(result);
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
//FIXME:error
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
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual([[result getIps] count], 0);

    startDate = [NSDate date];
    result = [request lookupHostFromServer:hostName error:&error];
    interval = [startDate timeIntervalSinceNow];
    XCTAssert(-interval < customizedTimeoutInterval);
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
    [requestScheduler setServerDisable:NO];
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 0;

    [ScheduleCenterTestHelper setTwoFirstIPWrongForTest];
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];

    XCTAssert(![requestScheduler isServerDisable]);
    [[HttpDnsService sharedInstance] getIpByHost:hostName];
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    sleep(0.02);//嗅探前
    //嗅探中
    sleep(customizedTimeoutInterval);
    //重试2次
    XCTAssert(![requestScheduler isServerDisable]);

    [HttpdnsRequestScheduler configureServerIPsAndResetActivatedIPTime];
}

/*!
 disable降级机制功能验证
 */
- (void)testDisable {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];
    [HttpDnsService sharedInstance].timeoutInterval = 5;
    NSTimeInterval customizedTimeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;

    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO];
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    scheduleCenter.activatedServerIPIndex = 0;

    [ScheduleCenterTestHelper setFourFirstIPWrongForTest];
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];
    [service getIpByHost:hostName];

    //重试2次+嗅探1次
    sleep(customizedTimeoutInterval + 1);

    //第2次嗅探失败
    [service getIpByHost:hostName];
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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];

    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO];
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
    });
}

/*!
 * 并发嗅探，结果一致，不会导致叠加
 */
- (void)testComplicatedlyAccessSameTwoWrongHostIP {
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];

    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO];
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];

    scheduleCenter.activatedServerIPIndex = 0;

    [ScheduleCenterTestHelper setTwoFirstIPWrongForTest];
    [HttpdnsRequestTestHelper zeroSnifferTimeForTest];

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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];

    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO];
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
    [[HttpDnsService sharedInstance] setHTTPSRequestEnabled:NO];

    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO];
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
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), [service getIpByHost:hostName]);
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
    [requestScheduler setServerDisable:NO];
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

        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), @([requestScheduler isServerDisable]));
        //嗅探正确的IP，但先返回nil。
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), [service getIpByHost:hostName]);
        sleep(customizedTimeoutInterval);
        //已经切到正确的IP
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), @(scheduleCenter.activatedServerIPIndex));
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
    [requestScheduler setServerDisable:NO];
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
    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), [service getIpByHost:hostName]);
    sleep(10);
    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), [service getIpByHost:hostName]);
    sleep(10);
    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), [service getIpByHost:hostName]);
    sleep(10);
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
    [ScheduleCenterTestHelper cancelAutoConnectToScheduleCenter];
    sleep(10);
    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    [HttpdnsScheduleCenterTestHelper shortMixConnectToScheduleCenterInterval];
    [HttpdnsScheduleCenterTestHelper shortAutoConnectToScheduleCenterInterval];
    __block NSTimeInterval timeInterval1 = 0;
    __block NSTimeInterval timeInterval2 = 0;
    __block NSTimeInterval timeInterval3 = 0;
    //第一次，超过最小间隔5S，可以更新。误差为1妙
    NSTimeInterval sleepTime = 1;
    [scheduleCenter forceUpdateIpListAsyncWithCallback:^(NSDictionary *result) {
        sleep(sleepTime);
        timeInterval1 = [ScheduleCenterTestHelper timeSinceCreateForScheduleCenterResult];
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), @(timeInterval1));
        XCTAssertNotNil(result);
        XCTAssertTrue(timeInterval1 > 0);
        XCTAssertTrue(timeInterval1 < sleepTime + 1);

        //未超过最小间隔，不可以更新
        [scheduleCenter forceUpdateIpListAsyncWithCallback:^(NSDictionary *result) {
            if ([result.allKeys count] > 0) {
                sleep(sleepTime);
                timeInterval2 = [ScheduleCenterTestHelper timeSinceCreateForScheduleCenterResult];
                NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), @(timeInterval2));
                XCTAssertNil(result);
                XCTAssertTrue(timeInterval2 > 0);
                XCTAssertTrue(timeInterval2 > timeInterval1 + sleepTime);
                XCTAssertTrue(timeInterval2 < timeInterval1 + sleepTime + 1);
                sleep(10);//让下一次，超过最小间隔，可以更新
                //超过最小间隔，可以更新
                [scheduleCenter forceUpdateIpListAsyncWithCallback:^(NSDictionary *result) {
                    if ([result.allKeys count] > 0) {
                        sleep(sleepTime);
                        XCTAssertTrue(YES);
                        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@==%@==%@", @(__PRETTY_FUNCTION__), @(__LINE__), @(timeInterval1), @(timeInterval2), @(timeInterval3));
                        XCTAssertNotNil(result);
                        timeInterval3 = [ScheduleCenterTestHelper timeSinceCreateForScheduleCenterResult];
                        XCTAssertTrue(timeInterval3<sleepTime+1);
                        XCTAssertTrue(timeInterval3 >= 0);
                        NOTIFY
                    } else {
                        NOTIFY
                    }
                }];
            } else {
                NOTIFY
            }
        }];
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
    //超过最小间隔，可以更新。误差为1妙
    [HttpdnsScheduleCenterTestHelper setFirstTwoWrongForScheduleCenterIPs];
    [scheduleCenter forceUpdateIpListAsyncWithCallback:^(NSDictionary *result) {
        NSArray *iplist;
        @try {
            iplist = result[@"service_ip"];
        } @catch (NSException *exception) {}
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@\%@", @(__PRETTY_FUNCTION__), @(__LINE__), result, iplist);
    }];
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
    HttpdnsRequestScheduler *requestScheduler =  [[HttpDnsService sharedInstance] requestScheduler];

    NSInteger code = 403;
    NSDictionary *errorInfo = @{
                                ALICLOUD_HTTPDNS_ERROR_MESSAGE_KEY : ALICLOUD_HTTPDNS_ERROR_SERVICE_LEVEL_DENY,
                                };
    NSError *error = [NSError errorWithDomain:NSStringFromClass([self class])
                                         code:code
                                     userInfo:errorInfo];

    [requestScheduler canNotResolveHost:hostName error:error isRetry:NO activatedServerIPIndex:0];
    sleep(20);
    XCTAssertNotNil([service getIpByHost:hostName]);
}

#pragma mark -
#pragma mark -  DB 缓存相关单元测试 Method

/**
 * 测试目的：持久化缓存的开关功能是否符合预期
 * 测试方法：
 * 1.调用getIpByHostAsync
 * 2.等待片刻，再次调用getIpByHostAsync，预期返回ip不为空
 * 3.持久化缓存中load相应数据，预期为空

 * 测试目的：getIpByHostAsync调用后是否缓存成功
 * 测试方法：
 * 1.setDBCacheEnable(true)
 * 2.调用getIpByHostAsync
 * 3.等待片刻，再次调用getIpByHostAsync，确保成功返回ip
 * 4.测试load是否正常

 * 测试目的：持久化缓存在初始化阶段和网络切换后是否成功加载
 * 测试方法：
 * 1.mService.setDBCacheEnable(true)
 * 2.模拟初始化状态
 * 3.在持久化缓存中构造数据
 * 4.调用getIpByHostAsync，预期返回构造数据
 * 5.模拟网络切换后的状态
 * 6.调用getIpByHostAsync，预期返回构造数据

 */
- (void)testDBEnableSwitch {
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = service.requestScheduler;

    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//    [service setCachedIPEnabled:YES];
    [requestScheduler loadIPsFromCacheSyncIfNeeded];
}

- (void)testLoadIPsFromCacheSyncIfNeeded {
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = service.requestScheduler;
    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//    [service setCachedIPEnabled:YES];
    [service getIpByHostAsync:@"www.aliyun.com"];
    sleep(2);

    int n = 10000;
    for (int i = 0; i < n; i++) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {

            [requestScheduler loadIPsFromCacheSyncIfNeeded];
            if (i == n -1) {
                NOTIFY
            }
        });

    }

    WAIT
}

/**
 * 测试目的：持久化缓存载入内存缓存后是否按预期TTL失效
 * 测试方法：
 * 1.setDBCacheEnable(true)
 * 2.构造容易过期的缓存记录
 * 3.调用getIpByHostAsync，预期能取到构造的ip
 * 4.等待过期
 * 5.再次调用getIpByHostAsync，预期拿到ip为空，并发起httpdns请求
 * 6.等待片刻，再次调用getIpByHostAsync，预期返回新的ip
 */
- (void)testDBTTLExpire {

    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = service.requestScheduler;

    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//    [service setCachedIPEnabled:YES];
    [requestScheduler loadIPsFromCacheSyncIfNeeded];
    HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
    HttpdnsHostRecord *hostRecord = [hostCacheStore hostRecordsWithCurrentCarrierForHost:hostName];

    HttpdnsIPCacheStore *IPCacheStore = [HttpdnsIPCacheStore sharedInstance];
    NSArray<HttpdnsIPRecord *> *IPRecords = [IPCacheStore IPRecordsForHostID:hostRecord.hostRecordId];
    HttpdnsIPRecord *IPRecord = IPRecords[0];
    //    XCTAssertNotNil([service getIpByHost:hostName]);
    sleep((unsigned int)IPRecord.TTL);
    XCTAssertNil([service getIpByHostAsync:hostName]);
    [requestScheduler loadIPsFromCacheSyncIfNeeded];
    XCTAssertNotNil([service getIpByHostAsync:hostName]);
}

/**
 * 测试目的：测试用户下线host后的边界情况
 * 测试方法：
 * 1.setDBCacheEnable(true)
 * 2.准备fake的容易过期数据
 * 3.store数据，模拟上次缓存场景
 * 4.调用getIpByHostAsync，第一次命中持久化缓存
 * 5.等待片刻，直到过期
 * 6.调用getIpByHostAsync，已经过期，发起httpdns请求，返回ip为空
 * 7.等待片刻
 * 8.load数据
 * 9.断言host为空
 */
- (void)testDB4 {
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = service.requestScheduler;
    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//    [service setCachedIPEnabled:YES];
    XCTAssertNotNil([service getIpByHost:hostName]);
    [requestScheduler cleanAllHostMemoryCache];
    [requestScheduler loadIPsFromCacheSyncIfNeeded];
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:hostName IPs:@[] IP6s:@[] TTL:0];
    HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
    [hostCacheStore insertHostRecords:@[hostRecord]];

    [requestScheduler cleanAllHostMemoryCache];
    [requestScheduler loadIPsFromCacheSyncIfNeeded];
}

/**
 * 测试目的：不同sp下，DB缓存load出来的host记录不相同
 * 测试方法：
 * 1.mService.setDBCacheEnable(true)
 * 2.调用getIpByHostAsync
 * 3.load HostRecord h2
 * 4.mock SpStatusMgr
 * 5.load HostRecord h3
 * 6.断言h2.id != h3.id
 */
- (void)testDB5 {

}
/**
 * 测试目的：本地轮询100次，确认sp信息读取是否都保持一致
 * 测试方法：
 * 1.mService.setDBCacheEnable(true)
 * 2.在持久化缓存中构造数据
 * 3.轮询调用100次getIpByHostAsync，断言返回结果一致
 */
- (void)testDB6 {
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = service.requestScheduler;

    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//区别于外部开关[service setCachedIPEnabled:YES];
    //同步网络请求，保存数据的数据库
    [service getIpByHost:hostName];
    //DB加载到内存
    [requestScheduler loadIPsFromCacheSyncIfNeeded];
    for (int i = 0; i < 10; i++) {
        NSString *IP1 = [service getIpByHostAsync:hostName];
        NSString *IP2 = [service getIpByHostAsync:hostName];
        XCTAssertNotNil(IP1);
        XCTAssertNotNil(IP2);
        XCTAssertTrue([IP1 isEqualToString:IP2]);
    }

    HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
    HttpdnsHostRecord *hostRecord = [hostCacheStore hostRecordsWithCurrentCarrierForHost:hostName];

    HttpdnsIPCacheStore *IPCacheStore = [HttpdnsIPCacheStore sharedInstance];
    NSArray<HttpdnsIPRecord *> *IPRecords = [IPCacheStore IPRecordsForHostID:hostRecord.hostRecordId];
    HttpdnsIPRecord *IPRecord = IPRecords[0];
    //    XCTAssertNotNil([service getIpByHost:hostName]);
    sleep((unsigned int)IPRecord.TTL);

    for (int i = 0; i < 10; i++) {
        NSString *IP1 = [service getIpByHostAsync:hostName];
        NSString *IP2 = [service getIpByHostAsync:hostName];
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@--%@", @(__PRETTY_FUNCTION__), @(__LINE__), IP1, IP2);
    }
}

/**
 * 测试目的：disable逻辑触发后，在合法缓存的情况下，是否返回空
 * 测试方法：
 * 1.mService.setDBCacheEnable(true)
 * 2.触发disable状态
 * 3.在持久化缓存中构造数据
 * 4.调用getIpByHostAsync，预期构造的host返回的ip为空
 */
- (void)testDBAndDisable {
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *requestScheduler = [service requestScheduler];
    [requestScheduler setServerDisable:NO];

    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//    [service setCachedIPEnabled:YES];
    [requestScheduler loadIPsFromCacheSyncIfNeeded];

    for (int i = 0; i < 10; i++) {
        NSString *IP1 = [service getIpByHostAsync:hostName];
        NSString *IP2 = [service getIpByHostAsync:hostName];
        XCTAssertNotNil(IP1);
        XCTAssertNotNil(IP2);
        XCTAssertTrue([IP1 isEqualToString:IP2]);
    }

    [requestScheduler setServerDisable:YES];

    for (int i = 0; i < 10; i++) {
        NSString *IP1 = [service getIpByHostAsync:hostName];
        NSString *IP2 = [service getIpByHostAsync:hostName];
        XCTAssertNil(IP1);
        XCTAssertNil(IP2);
    }
}

/**
 * 测试目的：API是否正常工作
 * 测试方法：
 * 1.准备数据
 * 2.store
 * 3.load
 * 4.断言结果正常
 * 5.clean
 * 6.断言结果正常
 */
- (void)testDBInsertManyTime {
    NSString *hostName = @"www.taobao.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    //XCTAssertNotNil([service getIpByHost:hostName]);
    HttpdnsRequestScheduler *requestScheduler = service.requestScheduler;
    [requestScheduler setServerDisable:NO];

    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//    [service setCachedIPEnabled:YES];
    HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
    //XCTAssertNotNil([service getIpByHostAsync:hostName]);

    [HttpdnsHostCacheStoreTestHelper shortCacheExpireTime];
    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), @(ALICLOUD_HTTPDNS_HOST_CACHE_MAX_CACHE_AGE));

    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//    [service setCachedIPEnabled:YES];
    //[requestScheduler loadIPsFromCacheSyncIfNeeded];

    for (int i = 0; i < 10; i++) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
             [service getIpByHostAsync:hostName];
             [service getIpByHostAsync:hostName];
            if (i == 9) {
                NOTIFY
            }
        });
    }
    WAIT
    sleep(15);

    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), [service getIpByHostAsync:hostName]);
    [requestScheduler cleanAllHostMemoryCache];
    //内部缓存开关，不触发加载DB到内存的操作
    [requestScheduler _setCachedIPEnabled:YES];//    [service setCachedIPEnabled:YES];
    //XCTAssertNotNil([service getIpByHostAsync:hostName]);
    //缓存过期
    sleep(5);
    [hostCacheStore cleanAllExpiredHostRecordsSync];
    [requestScheduler loadIPsFromCacheSyncIfNeeded];
    //HttpdnsHostRecord *hostRecord = [hostCacheStore hostRecordsWithCurrentCarrierForHost:hostName];
}

/**
 测试目的：测试beacon远程开关持久化功能
 测试方法：
 - 测试IP解析链路正常；
 - 模拟beacon获取到disabled状态；
 - 校验IP解析为为空；
 - 模拟beacon获取到enable状态；
 - 校验IP解析正常。
 */
- (void)testBeaconDisable {
    NSString *host = @"www.aliyun.com";
    HttpDnsService *service = [HttpDnsService sharedInstance];
    HttpdnsScheduleCenter *sc = [HttpdnsScheduleCenter sharedInstance];
    NSString *ip = [service getIpByHostAsync:host];
    XCTAssertNil(ip);
    sleep(5);
    ip = [service getIpByHostAsync:host];
    XCTAssertNotNil(ip);
    [sc setSDKDisableFromBeacon];
    sleep(5);
    ip = [service getIpByHostAsync:host];
    XCTAssertNil(ip);
    [sc clearSDKDisableFromBeacon];
    sleep(5);
    ip = [service getIpByHostAsync:host];
    XCTAssertNotNil(ip);
}

@end
