//
//  HttpdnsLogTests.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2026/7/8.
//  Copyright © 2026 alibaba-inc.com. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <stdatomic.h>
#import "HttpdnsLog_Internal.h"

// 阻塞式日志handler：进入log:后挂起，用于构造"日志调用进行中"的窗口
@interface HttpdnsLogBlockingHandler : NSObject <HttpdnsLoggerProtocol>

@property (nonatomic, strong) dispatch_semaphore_t enteredLogSemaphore;
@property (nonatomic, strong) dispatch_semaphore_t resumeSemaphore;

@end

@implementation HttpdnsLogBlockingHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        _enteredLogSemaphore = dispatch_semaphore_create(0);
        _resumeSemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (void)log:(NSString *)logStr {
    // 先把信号量取到局部变量，阻塞期间不再触碰self，
    // 避免handler被提前释放时测试代码自身产生野指针访问
    dispatch_semaphore_t entered = self.enteredLogSemaphore;
    dispatch_semaphore_t resume = self.resumeSemaphore;
    dispatch_semaphore_signal(entered);
    dispatch_semaphore_wait(resume, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
}

@end

// 带堆内存实例状态的handler：log:中必须解引用self，用于压力测试暴露野指针
@interface HttpdnsLogChurnHandler : NSObject <HttpdnsLoggerProtocol>

@property (nonatomic, copy) NSString *payload;

@end

@implementation HttpdnsLogChurnHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        _payload = [NSString stringWithFormat:@"payload-%p", (void *)self];
    }
    return self;
}

- (void)log:(NSString *)logStr {
    if (self.payload.length == 0) {
        NSLog(@"unexpected empty payload");
    }
}

@end

@interface HttpdnsLogTests : XCTestCase

@end

@implementation HttpdnsLogTests

- (void)tearDown {
    [HttpdnsLog unsetLogHandler];
    [super tearDown];
}

// 回归测试（对应线上崩溃）：log:执行期间handler被置空，正在被调用的对象不能被释放。
// 旧实现中outputToLogHandler不持有handler，unsetLogHandler会立刻释放对象，
// 导致后台线程向已释放对象发消息（EXC_BAD_ACCESS in objc_msgSend）。
- (void)testHandlerStaysAliveWhileLogCallInFlight {
    HttpdnsLogBlockingHandler *handler = [[HttpdnsLogBlockingHandler alloc] init];
    __weak HttpdnsLogBlockingHandler *weakHandler = handler;
    dispatch_semaphore_t entered = handler.enteredLogSemaphore;
    dispatch_semaphore_t resume = handler.resumeSemaphore;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);

    [HttpdnsLog setLogHandler:handler];
    // 只保留sLogHandler一个强引用，模拟业务方设置后不再持有handler的场景
    handler = nil;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [HttpdnsLog outputToLogHandler:@"test log"];
        dispatch_semaphore_signal(finished);
    });

    long waitResult = dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
    XCTAssertEqual(waitResult, 0, @"后台线程应已进入log:");

    // log:还在执行中时置空handler
    [HttpdnsLog unsetLogHandler];

    @autoreleasepool {
        XCTAssertNotNil(weakHandler, @"log:调用还在执行中，handler不应被释放");
    }

    dispatch_semaphore_signal(resume);
    waitResult = dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
    XCTAssertEqual(waitResult, 0, @"log:调用应正常返回");

    // 调用结束后handler应被释放，等待可能存在的autorelease延迟
    for (int i = 0; i < 100 && weakHandler != nil; i++) {
        @autoreleasepool {
            [NSThread sleepForTimeInterval:0.01];
        }
    }
    XCTAssertNil(weakHandler, @"log:调用结束后handler应被释放");
}

// 压力回归：多线程打日志的同时高频设置/置空handler，
// 旧实现下大概率触发向已释放对象发消息的崩溃
- (void)testConcurrentSetUnsetAndLogStress {
    const int readerCount = 4;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    dispatch_group_t group = dispatch_group_create();

    for (int i = 0; i < readerCount; i++) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            while ([deadline timeIntervalSinceNow] > 0) {
                @autoreleasepool {
                    if ([HttpdnsLog validLogHandler]) {
                        [HttpdnsLog outputToLogHandler:@"stress"];
                    }
                }
            }
        });
    }

    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        while ([deadline timeIntervalSinceNow] > 0) {
            @autoreleasepool {
                HttpdnsLogChurnHandler *churnHandler = [[HttpdnsLogChurnHandler alloc] init];
                [HttpdnsLog setLogHandler:churnHandler];
                [HttpdnsLog unsetLogHandler];
            }
        }
    });

    long result = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));
    XCTAssertEqual(result, 0, @"压力测试应在超时前完成且不崩溃");
}

// 回归：getFormattedDateTimeStr多线程并发调用不能崩溃且必须返回有效结果。
// 旧实现每次调用都对共享NSDateFormatter执行setDateFormat:，并发变异不安全。
- (void)testGetFormattedDateTimeStrConcurrency {
    const int threadCount = 8;
    const int iterationsPerThread = 2000;
    dispatch_group_t group = dispatch_group_create();
    __block atomic_int invalidCount;
    atomic_init(&invalidCount, 0);

    for (int t = 0; t < threadCount; t++) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            for (int i = 0; i < iterationsPerThread; i++) {
                @autoreleasepool {
                    NSString *str = [HttpdnsLog getFormattedDateTimeStr];
                    if (str.length == 0) {
                        atomic_fetch_add(&invalidCount, 1);
                    }
                }
            }
        });
    }

    long result = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)));
    XCTAssertEqual(result, 0, @"并发格式化应在超时前完成");
    XCTAssertEqual(atomic_load(&invalidCount), 0, @"并发格式化不应产生空结果");
}

@end
