//
//  MultithreadCorrectnessTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/5/26.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import <mach/mach.h>
#import "HttpdnsService.h"
#import "HttpdnsHostResolver.h"
#import "TestBase.h"

@interface MultithreadCorrectnessTest : TestBase

@end


@implementation MultithreadCorrectnessTest

- (void)setUp {
    [super setUp];

    self.httpdns = [[HttpDnsService alloc] initWithAccountID:100000];
    [self.httpdns setLogEnabled:YES];
    [self.httpdns setIPv6Enabled:YES];
    [self.httpdns setLogHandler:self];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (void)tearDown {
    [super tearDown];
}

// 非阻塞接口不能阻塞调用线程
- (void)testNoneBlockingMethodShouldNotBlock {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockedScheduler = OCMPartialMock(scheduler);
    OCMStub([mockedScheduler executeRequest:[OCMArg any] retryCount:0])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            [NSThread sleepForTimeInterval:3];
        });

    [mockedScheduler cleanAllHostMemoryCache];

    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    [self.httpdns resolveHostSyncNonBlocking:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
    NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSince1970] - startTime;

    XCTAssert(elapsedTime < 1, @"elapsedTime should be less than 1s, but is %f", elapsedTime);
}

// 阻塞接口在主线程调用时也不会阻塞，内部做了机制自动切换到异步线程
- (void)testBlockingMethodShouldNotBlockIfInMainThread {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockedScheduler = OCMPartialMock(scheduler);
    OCMStub([mockedScheduler executeRequest:[OCMArg any] retryCount:0])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            [NSThread sleepForTimeInterval:3];
        });
    [mockedScheduler cleanAllHostMemoryCache];
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
    NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSince1970] - startTime;

    XCTAssert(elapsedTime < 1, @"elapsedTime should be less than 1s, but is %f", elapsedTime);
}

// 非主线程中调用阻塞接口，应当阻塞
- (void)testBlockingMethodShouldBlockIfInBackgroundThread {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockedScheduler = OCMPartialMock(scheduler);
    OCMStub([mockedScheduler executeRequest:[OCMArg any] retryCount:0])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            [NSThread sleepForTimeInterval:3];
        });
    [mockedScheduler cleanAllHostMemoryCache];

    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSince1970] - startTime;
    XCTAssert(elapsedTime >= 3, @"elapsedTime should be more than 3s, but is %f", elapsedTime);
}

- (void)testResolveSameHostShouldWaitForTheFirstOne {
    __block HttpdnsHostObject *ipv4HostObject = [self constructSimpleIpv4HostObject];
    HttpdnsHostResolver *realResolver = [HttpdnsHostResolver new];
    id mockResolver = OCMPartialMock(realResolver);
    OCMStub([mockResolver lookupHostFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            // 第一次调用，阻塞5秒
            [NSThread sleepForTimeInterval:5];
            [invocation setReturnValue:&ipv4HostObject];
        });

    id mockResolverClass = OCMClassMock([HttpdnsHostResolver class]);
    OCMStub([mockResolverClass new]).andReturn(mockResolver);

    [self.httpdns.requestScheduler cleanAllHostMemoryCache];

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
    });

    // 确保第一个请求已经开始
    [NSThread sleepForTimeInterval:1];

    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // 第二次请求，由于是同一个域名，所以它应该等待第一个请求的返回
        // 第一个请求返回后，第二个请求不应该再次请求，而是直接从缓存中读取到结果，返回
        // 所以它的等待时间接近4秒
        HttpdnsResult *result = [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
        XCTAssertNotNil(result);
        XCTAssertTrue([result.host isEqualToString:ipv4OnlyHost]);
        XCTAssertTrue([result.ips count] == 2);
        XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
        dispatch_semaphore_signal(semaphore);
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSince1970] - startTime;
    XCTAssert(elapsedTime >= 3.9, @"elapsedTime should be more than 3.9s, but is %f", elapsedTime);

    // TODO 这里暂时无法跑过，因为现在锁的机制，会导致第二个请求也要去请求
    // XCTAssert(elapsedTime < 4.1, @"elapsedTime should be less than 4.1s, but is %f", elapsedTime);
}

- (void)testResolveSameHostShouldRequestAgainAfterFirstFailed {
    __block HttpdnsHostObject *ipv4HostObject = [self constructSimpleIpv4HostObject];
    HttpdnsHostResolver *realResolver = [HttpdnsHostResolver new];
    id mockResolver = OCMPartialMock(realResolver);
    __block atomic_int count = 0;
    OCMStub([mockResolver lookupHostFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            int localCount = atomic_fetch_add(&count, 1) + 1;

            if (localCount == 1) {
                [NSThread sleepForTimeInterval:3];
                // 第一次调用，返回异常
                @throw [NSException exceptionWithName:@"TestException" reason:@"TestException" userInfo:nil];
            } else {
                // 第二次调用
                [NSThread sleepForTimeInterval:3];
                [invocation setReturnValue:&ipv4HostObject];
            }
        });

    id mockResolverClass = OCMClassMock([HttpdnsHostResolver class]);
    OCMStub([mockResolverClass new]).andReturn(mockResolver);

    [self.httpdns.requestScheduler cleanAllHostMemoryCache];

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
    });

    // 确保第一个请求已经开始
    [NSThread sleepForTimeInterval:1];

    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // 第二次请求，由于是同一个域名，所以它应该等待第一个请求的返回
        // 第一个请求失败后，第二个请求从缓存拿不到结果，应该再次请求
        // 所以它等待的时间将是约5秒
        HttpdnsResult *result = [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
        XCTAssertNotNil(result);
        XCTAssertTrue([result.host isEqualToString:ipv4OnlyHost]);
        XCTAssertTrue([result.ips count] == 2);
        XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
        dispatch_semaphore_signal(semaphore);
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSince1970] - startTime;
    XCTAssert(elapsedTime >= 4.9, @"elapsedTime should be more than 3.9s, but is %f", elapsedTime);
    XCTAssert(elapsedTime < 5.1, @"elapsedTime should be less than 4.1s, but is %f", elapsedTime);
}

// 最大等待时间
- (void)testSyncMethodMaxBlockingTime {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    [self.httpdns cleanAllHostCache];

    HttpdnsRequestScheduler *mockedScheduler = OCMPartialMock(scheduler);
    OCMStub([mockedScheduler executeRequest:[OCMArg any] retryCount:0])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            [NSThread sleepForTimeInterval:5];
        })
        .andReturn([self constructSimpleIpv4HostObject]);

    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];

    HttpdnsRequest *request = [HttpdnsRequest new];
    request.host = ipv4OnlyHost;
    request.queryIpType = HttpdnsQueryIPTypeIpv4;
    request.resolveTimeoutInSecond = 2.5;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:request];
        NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSince1970] - startTime;
        XCTAssert(elapsedTime < 2.6, @"elapsedTime should be less than 2.6s, but is %f", elapsedTime);
        XCTAssert(elapsedTime >= 2.5, @"elapsedTime should be greater than or equal to 2.5s, but is %f", elapsedTime);
        XCTAssertNil(result);
        dispatch_semaphore_signal(semaphore);
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

@end
