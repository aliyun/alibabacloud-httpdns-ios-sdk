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

@interface MultithreadCorrectnessTest : TestBase <HttpdnsTTLDelegate, HttpdnsLoggerProtocol>

@end


static NSMutableArray *mockedObjects;

@implementation MultithreadCorrectnessTest

static NSDictionary<NSString *, NSString *> *hostNameIpPrefixMap;

+ (void)setUp {
    hostNameIpPrefixMap = @{
        @"v4host1.onlyforhttpdnstest.run.place": @"0.0.1",
        @"v4host2.onlyforhttpdnstest.run.place": @"0.0.2",
        @"v4host3.onlyforhttpdnstest.run.place": @"0.0.3",
        @"v4host4.onlyforhttpdnstest.run.place": @"0.0.4",
        @"v4host5.onlyforhttpdnstest.run.place": @"0.0.5"
    };
}

- (void)setUp {
    [super setUp];

    mockedObjects = [NSMutableArray array];

    self.httpdns = [[HttpDnsService alloc] initWithAccountID:100000];
    [self.httpdns setLogEnabled:YES];
    [self.httpdns setIPv6Enabled:YES];
    [self.httpdns setTtlDelegate:self];
    [self.httpdns setLogHandler:self];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (void)tearDown {
    [super tearDown];
}

- (int64_t)httpdnsHost:(NSString *)host ipType:(AlicloudHttpDNS_IPType)ipType ttl:(int64_t)ttl {
    // 为了在并发测试中域名快速过期，将ttl设置为随机1-4秒
    return arc4random_uniform(4) + 1;
}

- (void)log:(NSString *)logStr {
    mach_port_t threadID = mach_thread_self();
    NSString *threadIDString = [NSString stringWithFormat:@"%x", threadID];
    printf("%ld-%s %s\n", (long)[[NSDate date] timeIntervalSince1970], [threadIDString UTF8String], [logStr UTF8String]);
}

- (void)testNoneBlockingMethodShouldNotBlock {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockedScheduler = OCMPartialMock(scheduler);
    OCMStub([mockedScheduler executeRequest:[OCMArg any] retryCount:0 activatedServerIPIndex:0 error:nil])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            [NSThread sleepForTimeInterval:3];
        });
    [mockedObjects addObject:mockedScheduler];

    [mockedScheduler cleanAllHostMemoryCache];

    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    [self.httpdns resolveHostSyncNonBlocking:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
    NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSince1970] - startTime;

    XCTAssert(elapsedTime < 1, @"elapsedTime should be less than 1s, but is %f", elapsedTime);
}

- (void)testBlockingMethodShouldNotBlockIfInMainThread {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockedScheduler = OCMPartialMock(scheduler);
    OCMStub([mockedScheduler executeRequest:[OCMArg any] retryCount:0 activatedServerIPIndex:0 error:nil])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            [NSThread sleepForTimeInterval:3];
        });
    [mockedObjects addObject:mockedScheduler];
    [mockedScheduler cleanAllHostMemoryCache];
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];
    NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSince1970] - startTime;

    XCTAssert(elapsedTime < 1, @"elapsedTime should be less than 1s, but is %f", elapsedTime);
}

- (void)testBlockingMethodShouldBlockIfInBackgroundThread {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockedScheduler = OCMPartialMock(scheduler);
    OCMStub([mockedScheduler executeRequest:[OCMArg any] retryCount:0 activatedServerIPIndex:0 error:nil])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            [NSThread sleepForTimeInterval:3];
        });
    [mockedObjects addObject:mockedScheduler];
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
    OCMStub([mockResolver lookupHostFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer] activatedServerIPIndex:0])
        .ignoringNonObjectArgs()
        .andDo(^(NSInvocation *invocation) {
            // 第一次调用，阻塞5秒
            [NSThread sleepForTimeInterval:5];
            [invocation setReturnValue:&ipv4HostObject];
        });

    id mockResolverClass = OCMClassMock([HttpdnsHostResolver class]);
    OCMStub([mockResolverClass new]).andReturn(mockResolver);

    [mockedObjects addObject:mockResolver];
    [mockedObjects addObject:mockResolverClass];

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
    XCTAssert(elapsedTime < 4.1, @"elapsedTime should be less than 4.1s, but is %f", elapsedTime);
}

- (void)testResolveSameHostShouldRequestAgainAfterFirstFailed {
    __block HttpdnsHostObject *ipv4HostObject = [self constructSimpleIpv4HostObject];
    HttpdnsHostResolver *realResolver = [HttpdnsHostResolver new];
    id mockResolver = OCMPartialMock(realResolver);
    __block atomic_int count = 0;
    OCMStub([mockResolver lookupHostFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer] activatedServerIPIndex:0])
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

    [mockedObjects addObject:mockResolver];
    [mockedObjects addObject:mockResolverClass];

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


- (void)testNormalMultipleHostsResolve {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [hostNameIpPrefixMap enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull host, NSString * _Nonnull ipPrefix, BOOL * _Nonnull stop) {
            HttpdnsResult *result = [self.httpdns resolveHostSync:host byIpType:HttpdnsQueryIPTypeIpv4];
            XCTAssertNotNil(result);
            XCTAssertTrue([result.host isEqualToString:host]);
            NSString *firstIp = [result firstIpv4Address];
            if (![firstIp hasPrefix:ipPrefix]) {
                printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [host UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
            }
            XCTAssertTrue([firstIp hasPrefix:ipPrefix]);
        }];
        dispatch_semaphore_signal(semaphore);
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testNonblockingMethodShouldNotBlockDuringMultithreadLongRun {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval testDuration = 10;
    int threadCountForEachType = 4;

    for (int i = 0; i < threadCountForEachType; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while ([[NSDate date] timeIntervalSince1970] - startTime < testDuration) {
                NSString *host = [hostNameIpPrefixMap allKeys][arc4random_uniform((uint32_t)[hostNameIpPrefixMap count])];
                NSString *ipPrefix = hostNameIpPrefixMap[host];

                long long executeStartTimeInMs = [[NSDate date] timeIntervalSince1970] * 1000;
                HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:host byIpType:HttpdnsQueryIPTypeIpv4];
                long long executeEndTimeInMs = [[NSDate date] timeIntervalSince1970] * 1000;
                // 非阻塞接口任何情况下不应该阻塞超过10ms
                XCTAssertLessThan(executeEndTimeInMs - executeStartTimeInMs, 10);
                if (result) {
                    XCTAssertNotNil(result);
                    XCTAssertTrue([result.host isEqualToString:host]);
                    NSString *firstIp = [result firstIpv4Address];
                    if (![firstIp hasPrefix:ipPrefix]) {
                        printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [host UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
                    }
                    XCTAssertTrue([firstIp hasPrefix:ipPrefix]);
                }
                [NSThread sleepForTimeInterval:0.1];
            }
        });
    }

    [NSThread sleepForTimeInterval:testDuration + 1];
}

- (void)testMultithreadAndMultiHostResolvingForALongRun {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval testDuration = 10;
    int threadCountForEachType = 4;

    for (int i = 0; i < threadCountForEachType; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while ([[NSDate date] timeIntervalSince1970] - startTime < testDuration) {
                NSString *host = [hostNameIpPrefixMap allKeys][arc4random_uniform((uint32_t)[hostNameIpPrefixMap count])];
                NSString *ipPrefix = hostNameIpPrefixMap[host];

                HttpdnsResult *result = [self.httpdns resolveHostSync:host byIpType:HttpdnsQueryIPTypeIpv4];
                XCTAssertNotNil(result);
                XCTAssertTrue([result.host isEqualToString:host]);
                NSString *firstIp = [result firstIpv4Address];
                if (![firstIp hasPrefix:ipPrefix]) {
                    printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [host UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
                }
                XCTAssertTrue([firstIp hasPrefix:ipPrefix]);

                [NSThread sleepForTimeInterval:0.1];
            }
        });
    }

    for (int i = 0; i < threadCountForEachType; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while ([[NSDate date] timeIntervalSince1970] - startTime < testDuration) {
                NSString *host = [hostNameIpPrefixMap allKeys][arc4random_uniform((uint32_t)[hostNameIpPrefixMap count])];
                NSString *ipPrefix = hostNameIpPrefixMap[host];

                [self.httpdns resolveHostAsync:host byIpType:HttpdnsQueryIPTypeIpv4 completionHandler:^(HttpdnsResult *result) {
                    XCTAssertNotNil(result);
                    XCTAssertTrue([result.host isEqualToString:host]);
                    NSString *firstIp = [result firstIpv4Address];
                    if (![firstIp hasPrefix:ipPrefix]) {
                        printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [host UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
                    }
                    XCTAssertTrue([firstIp hasPrefix:ipPrefix]);
                }];
                [NSThread sleepForTimeInterval:0.1];
            }
        });
    }

    for (int i = 0; i < threadCountForEachType; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while ([[NSDate date] timeIntervalSince1970] - startTime < testDuration) {
                NSString *host = [hostNameIpPrefixMap allKeys][arc4random_uniform((uint32_t)[hostNameIpPrefixMap count])];
                NSString *ipPrefix = hostNameIpPrefixMap[host];
                HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:host byIpType:HttpdnsQueryIPTypeIpv4];
                if (result) {
                    XCTAssertTrue([result.host isEqualToString:host]);
                    NSString *firstIp = [result firstIpv4Address];
                    if (![firstIp hasPrefix:ipPrefix]) {
                        printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [host UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
                    }
                    XCTAssertTrue([firstIp hasPrefix:ipPrefix]);
                }
                [NSThread sleepForTimeInterval:0.1];
            }
        });
    }

    sleep(testDuration + 1);
}

// 指定查询both，但域名都只配置了ipv4
// 这种情况下，会自动打标该域名无ipv6，后续的结果只会包含ipv4地址
- (void)testMultithreadAndMultiHostResolvingForALongRunBySpecifyBothIpv4AndIpv6 {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval testDuration = 10;
    int threadCountForEachType = 4;

    // 计数时有并发冲突的可能，但只是测试，不用过于严谨
    __block int syncCount = 0, asyncCount = 0, syncNonBlockingCount = 0;

    for (int i = 0; i < threadCountForEachType; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while ([[NSDate date] timeIntervalSince1970] - startTime < testDuration) {
                NSString *host = [hostNameIpPrefixMap allKeys][arc4random_uniform((uint32_t)[hostNameIpPrefixMap count])];
                NSString *ipPrefix = hostNameIpPrefixMap[host];

                HttpdnsResult *result = [self.httpdns resolveHostSync:host byIpType:HttpdnsQueryIPTypeBoth];
                XCTAssertNotNil(result);
                XCTAssertTrue(!result.hasIpv6Address);
                XCTAssertTrue([result.host isEqualToString:host]);
                NSString *firstIp = [result firstIpv4Address];
                if (![firstIp hasPrefix:ipPrefix]) {
                    printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [host UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
                }
                XCTAssertTrue([firstIp hasPrefix:ipPrefix]);

                syncCount++;
                [NSThread sleepForTimeInterval:0.1];
            }
        });
    }

    for (int i = 0; i < threadCountForEachType; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while ([[NSDate date] timeIntervalSince1970] - startTime < testDuration) {
                NSString *host = [hostNameIpPrefixMap allKeys][arc4random_uniform((uint32_t)[hostNameIpPrefixMap count])];
                NSString *ipPrefix = hostNameIpPrefixMap[host];

                [self.httpdns resolveHostAsync:host byIpType:HttpdnsQueryIPTypeBoth completionHandler:^(HttpdnsResult *result) {
                    XCTAssertNotNil(result);
                    XCTAssertTrue(!result.hasIpv6Address);
                    XCTAssertTrue([result.host isEqualToString:host]);
                    NSString *firstIp = [result firstIpv4Address];
                    if (![firstIp hasPrefix:ipPrefix]) {
                        printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [host UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
                    }
                    XCTAssertTrue([firstIp hasPrefix:ipPrefix]);

                    asyncCount++;
                }];
                [NSThread sleepForTimeInterval:0.1];
            }
        });
    }

    for (int i = 0; i < threadCountForEachType; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while ([[NSDate date] timeIntervalSince1970] - startTime < testDuration) {
                NSString *host = [hostNameIpPrefixMap allKeys][arc4random_uniform((uint32_t)[hostNameIpPrefixMap count])];
                NSString *ipPrefix = hostNameIpPrefixMap[host];

                HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:host byIpType:HttpdnsQueryIPTypeBoth];
                if (result) {
                    XCTAssertTrue([result.host isEqualToString:host]);
                    XCTAssertTrue(!result.hasIpv6Address);
                    NSString *firstIp = [result firstIpv4Address];
                    if (![firstIp hasPrefix:ipPrefix]) {
                        printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [host UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
                    }
                    XCTAssertTrue([firstIp hasPrefix:ipPrefix]);
                }

                syncNonBlockingCount++;
                [NSThread sleepForTimeInterval:0.1];
            }
        });
    }

    sleep(testDuration + 1);

    int theoreticalCount = threadCountForEachType * (testDuration / 0.1);

    // printf all the counts
    printf("syncCount: %d, asyncCount: %d, syncNonBlockingCount: %d, theoreticalCount: %d\n", syncCount, asyncCount, syncNonBlockingCount, theoreticalCount);
}

@end
