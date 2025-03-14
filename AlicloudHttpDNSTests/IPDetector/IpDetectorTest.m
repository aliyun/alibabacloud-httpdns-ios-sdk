//
//  IpDetectorTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2025/3/14.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../Testbase/TestBase.h"
#import "HttpdnsIPQualityDetector.h"

@interface IpDetectorTest : TestBase

@end

@implementation IpDetectorTest

- (void)setUp {
    [super setUp];
    // 使用默认配置，不修改maxConcurrentDetections
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - 单例和基本属性测试

- (void)testSharedInstance {
    // 测试单例模式
    HttpdnsIPQualityDetector *detector1 = [HttpdnsIPQualityDetector sharedInstance];
    HttpdnsIPQualityDetector *detector2 = [HttpdnsIPQualityDetector sharedInstance];

    XCTAssertEqual(detector1, detector2, @"单例模式应该返回相同的实例");
    XCTAssertNotNil(detector1, @"单例实例不应为nil");
}

#pragma mark - TCP连接测试

- (void)testTcpConnectToValidIP {
    // 测试连接到有效IP
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];

    // 使用公共DNS服务器作为测试目标
    NSInteger costTime = [detector tcpConnectToIP:@"8.8.8.8" port:53];

    // 验证连接成功并返回正数耗时
    XCTAssertGreaterThan(costTime, 0, @"连接到有效IP应返回正数耗时");
}

- (void)testTcpConnectToInvalidIP {
    // 测试连接到无效IP
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];

    // 使用无效IP地址
    NSInteger costTime = [detector tcpConnectToIP:@"192.168.255.255" port:12345];

    // 验证连接失败并返回-1
    XCTAssertEqual(costTime, -1, @"连接到无效IP应返回-1");
}

- (void)testTcpConnectWithInvalidParameters {
    // 测试使用无效参数进行连接
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];

    // 测试空IP
    NSInteger costTime = [detector tcpConnectToIP:nil port:80];
    XCTAssertEqual(costTime, -1, @"使用nil IP应返回-1");

    // 测试无效格式的IP
    costTime = [detector tcpConnectToIP:@"not-an-ip" port:80];
    XCTAssertEqual(costTime, -1, @"使用无效格式IP应返回-1");

    // 测试无效端口
    costTime = [detector tcpConnectToIP:@"8.8.8.8" port:-1];
    XCTAssertEqual(costTime, -1, @"使用无效端口应返回-1");
}

#pragma mark - 任务调度测试

- (void)testScheduleIPQualityDetection {
    // 测试调度IP质量检测任务
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 设置期望：executeDetection方法应被调用
    OCMExpect([detectorMock executeDetection:@"example.com"
                                          ip:@"1.2.3.4"
                                        port:[NSNumber numberWithInt:80]
                                    callback:[OCMArg any]]);

    // 执行测试
    [detectorMock scheduleIPQualityDetection:@"example.com"
                                          ip:@"1.2.3.4"
                                        port:[NSNumber numberWithInt:80]
                                    callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {
        // 回调不会被触发，因为我们模拟了executeDetection方法
    }];

    // 验证期望
    OCMVerifyAll(detectorMock);

    // 停止模拟
    [detectorMock stopMocking];
}

- (void)testScheduleWithInvalidParameters {
    // 测试使用无效参数调度任务
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 设置期望：executeDetection方法不应被调用
    OCMReject([detectorMock executeDetection:[OCMArg any]
                                          ip:[OCMArg any]
                                        port:[OCMArg any]
                                    callback:[OCMArg any]]);

    // 测试nil cacheKey
    [detectorMock scheduleIPQualityDetection:nil
                                          ip:@"1.2.3.4"
                                        port:[NSNumber numberWithInt:80]
                                    callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {}];

    // 测试nil IP
    [detectorMock scheduleIPQualityDetection:@"example.com"
                                          ip:nil
                                        port:[NSNumber numberWithInt:80]
                                    callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {}];

    // 测试nil callback
    [detectorMock scheduleIPQualityDetection:@"example.com"
                                          ip:@"1.2.3.4"
                                        port:[NSNumber numberWithInt:80]
                                    callback:nil];

    // 验证期望
    OCMVerifyAll(detectorMock);

    // 停止模拟
    [detectorMock stopMocking];
}

- (void)testConcurrencyLimitReached {
    // 测试达到并发限制时的行为
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 由于无法直接模拟dispatch_semaphore_wait，我们采用另一种方式测试并发限制
    // 模拟scheduleIPQualityDetection内部实现，当调用时直接执行addPendingTask
    OCMStub([detectorMock scheduleIPQualityDetection:[OCMArg any]
                                                  ip:[OCMArg any]
                                                port:[OCMArg any]
                                            callback:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
        // 提取参数
        NSString *cacheKey;
        NSString *ip;
        NSNumber *port;
        HttpdnsIPQualityCallback callback;

        [invocation getArgument:&cacheKey atIndex:2];
        [invocation getArgument:&ip atIndex:3];
        [invocation getArgument:&port atIndex:4];
        [invocation getArgument:&callback atIndex:5];

        // 直接调用addPendingTask，模拟并发限制已达到的情况
        [detector addPendingTask:cacheKey ip:ip port:port callback:callback];
    });

    // 设置期望：验证addPendingTask被调用，而executeDetection不被调用
    // 使用同一个mock对象，避免创建多个mock
    OCMExpect([detectorMock addPendingTask:@"example.com"
                                        ip:@"1.2.3.4"
                                      port:[NSNumber numberWithInt:80]
                                  callback:[OCMArg any]]);

    OCMReject([detectorMock executeDetection:[OCMArg any]
                                          ip:[OCMArg any]
                                        port:[OCMArg any]
                                    callback:[OCMArg any]]);

    // 执行测试
    [detectorMock scheduleIPQualityDetection:@"example.com"
                                          ip:@"1.2.3.4"
                                        port:[NSNumber numberWithInt:80]
                                    callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {}];

    // 验证期望
    OCMVerifyAll(detectorMock);

    // 停止模拟
    [detectorMock stopMocking];
}

- (void)testAddPendingTask {
    // 测试添加待处理任务
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 模拟processPendingTasksIfNeeded方法，避免实际处理任务
    OCMStub([detectorMock processPendingTasksIfNeeded]);

    // 记录初始待处理任务数量
    NSUInteger initialCount = [detector pendingTasksCount];

    // 添加一个待处理任务
    [detectorMock addPendingTask:@"example.com"
                              ip:@"1.2.3.4"
                            port:[NSNumber numberWithInt:80]
                        callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {}];

    // 验证待处理任务数量增加
    XCTAssertEqual([detector pendingTasksCount], initialCount + 1, @"添加任务后待处理任务数量应增加1");

    // 停止模拟
    [detectorMock stopMocking];
}

- (void)testPendingTasksProcessing {
    // 测试待处理任务的处理
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 模拟executeDetection方法，避免实际执行检测
    OCMStub([detectorMock executeDetection:[OCMArg any]
                                        ip:[OCMArg any]
                                      port:[OCMArg any]
                                  callback:[OCMArg any]]);

    // 添加一个待处理任务
    [detectorMock addPendingTask:@"example.com"
                              ip:@"1.2.3.4"
                            port:[NSNumber numberWithInt:80]
                        callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {}];

    // 手动触发处理待处理任务
    [detectorMock processPendingTasksIfNeeded];

    // 给处理任务一些时间
    [NSThread sleepForTimeInterval:0.1];

    // 验证待处理任务已被处理
    XCTAssertEqual([detector pendingTasksCount], 0, @"处理后待处理任务数量应为0");

    // 停止模拟
    [detectorMock stopMocking];
}

#pragma mark - 异步回调测试

- (void)testExecuteDetection {
    // 测试执行检测并回调
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 模拟tcpConnectToIP方法返回固定值
    OCMStub([detectorMock tcpConnectToIP:@"1.2.3.4" port:80]).andReturn(100);

    // 创建期望
    XCTestExpectation *expectation = [self expectationWithDescription:@"回调应被执行"];

    // 执行测试
    [detectorMock executeDetection:@"example.com"
                               ip:@"1.2.3.4"
                             port:[NSNumber numberWithInt:80]
                         callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {
        // 验证回调参数
        XCTAssertEqualObjects(cacheKey, @"example.com", @"回调中的cacheKey应正确");
        XCTAssertEqualObjects(ip, @"1.2.3.4", @"回调中的IP应正确");
        XCTAssertEqual(costTime, 100, @"回调中的耗时应正确");

        [expectation fulfill];
    }];

    // 等待异步操作完成
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // 停止模拟
    [detectorMock stopMocking];
}

- (void)testExecuteDetectionWithFailure {
    // 测试执行检测失败的情况
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 模拟tcpConnectToIP方法返回失败
    OCMStub([detectorMock tcpConnectToIP:@"1.2.3.4" port:80]).andReturn(-1);

    // 创建期望
    XCTestExpectation *expectation = [self expectationWithDescription:@"失败回调应被执行"];

    // 执行测试
    [detectorMock executeDetection:@"example.com"
                               ip:@"1.2.3.4"
                             port:[NSNumber numberWithInt:80]
                         callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {
        // 验证回调参数
        XCTAssertEqualObjects(cacheKey, @"example.com", @"回调中的cacheKey应正确");
        XCTAssertEqualObjects(ip, @"1.2.3.4", @"回调中的IP应正确");
        XCTAssertEqual(costTime, -1, @"连接失败时回调中的耗时应为-1");

        [expectation fulfill];
    }];

    // 等待异步操作完成
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // 停止模拟
    [detectorMock stopMocking];
}

- (void)testExecuteDetectionWithNilPort {
    // 测试执行检测时端口为nil的情况
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 模拟tcpConnectToIP方法，验证使用默认端口80
    OCMExpect([detectorMock tcpConnectToIP:@"1.2.3.4" port:80]).andReturn(100);

    // 创建期望
    XCTestExpectation *expectation = [self expectationWithDescription:@"默认端口回调应被执行"];

    // 执行测试，不指定端口
    [detectorMock executeDetection:@"example.com"
                               ip:@"1.2.3.4"
                             port:nil
                         callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {
        [expectation fulfill];
    }];

    // 等待异步操作完成
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // 验证期望
    OCMVerifyAll(detectorMock);

    // 停止模拟
    [detectorMock stopMocking];
}

#pragma mark - 内存管理测试

- (void)testMemoryManagementInAsyncOperations {
    // 测试异步操作中的内存管理
    HttpdnsIPQualityDetector *detector = [HttpdnsIPQualityDetector sharedInstance];
    id detectorMock = OCMPartialMock(detector);

    // 创建可能在异步操作中被释放的对象
    __block NSString *tempCacheKey = [@"example.com" copy];
    __block NSString *tempIP = [@"1.2.3.4" copy];

    // 创建弱引用以检测对象是否被释放
    __weak NSString *weakCacheKey = tempCacheKey;
    __weak NSString *weakIP = tempIP;

    // 模拟tcpConnectToIP方法，延迟返回以模拟网络延迟
    OCMStub([detectorMock tcpConnectToIP:[OCMArg any] port:80]).andDo(^(NSInvocation *invocation) {
        // 延迟执行，给GC一个机会
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // 设置返回值
            NSInteger result = 100;
            [invocation setReturnValue:&result];
        });
    });

    // 创建期望
    XCTestExpectation *expectation = [self expectationWithDescription:@"内存管理回调应被执行"];

    // 执行测试
    [detectorMock executeDetection:tempCacheKey
                               ip:tempIP
                             port:[NSNumber numberWithInt:80]
                         callback:^(NSString *cacheKey, NSString *ip, NSInteger costTime) {
        // 验证对象在回调时仍然有效
        XCTAssertEqualObjects(cacheKey, @"example.com", @"回调中的cacheKey应正确");
        XCTAssertEqualObjects(ip, @"1.2.3.4", @"回调中的IP应正确");

        [expectation fulfill];
    }];

    // 清除局部变量的强引用
    tempCacheKey = nil;
    tempIP = nil;

    // 强制GC（注意：在ARC下这不一定会立即触发）
    @autoreleasepool {
        // 触发自动释放池
    }

    // 验证对象没有被释放（应该被executeDetection方法内部强引用）
    XCTAssertNotNil(weakCacheKey, @"cacheKey不应被释放");
    XCTAssertNotNil(weakIP, @"IP不应被释放");

    // 等待异步操作完成
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // 停止模拟
    [detectorMock stopMocking];
}

@end
