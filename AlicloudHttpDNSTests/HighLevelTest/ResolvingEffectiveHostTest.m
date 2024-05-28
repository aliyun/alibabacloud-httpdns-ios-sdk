//
//  ResolvingEffectiveHostTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/5/28.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import <mach/mach.h>
#import "HttpdnsService.h"
#import "HttpdnsHostResolver.h"
#import "TestBase.h"

@interface ResolvingEffectiveHostTest : TestBase<HttpdnsTTLDelegate>

@end


@implementation ResolvingEffectiveHostTest

+ (void)setUp {
    [super setUp];
}

- (void)setUp {
    [super setUp];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        self.httpdns = [[HttpDnsService alloc] initWithAccountID:100000];
    });

    [self.httpdns setLogEnabled:YES];
    [self.httpdns setIPv6Enabled:YES];
    [self.httpdns setReuseExpiredIPEnabled:NO];

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

- (void)testNormalMultipleHostsResolve {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    // 使用正常解析到的ttl
    [self.httpdns setTtlDelegate:nil];

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [hostNameIpPrefixMap enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull host, NSString * _Nonnull ipPrefix, BOOL * _Nonnull stop) {
            HttpdnsResult *result = [self.httpdns resolveHostSync:host byIpType:HttpdnsQueryIPTypeIpv4];
            XCTAssertNotNil(result);
            XCTAssertTrue([result.host isEqualToString:host]);
            XCTAssertGreaterThan(result.ttl, 0);
            // 同步接口，不复用过期ip的情况下，解析出的ip一定是未过期的
            XCTAssertLessThan([[NSDate date] timeIntervalSince1970], result.lastUpdatedTimeInterval + result.ttl);
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
    int threadCountForEachType = 5;

    for (int i = 0; i < threadCountForEachType; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while ([[NSDate date] timeIntervalSince1970] - startTime < testDuration) {
                NSString *host = [hostNameIpPrefixMap allKeys][arc4random_uniform((uint32_t)[hostNameIpPrefixMap count])];
                NSString *ipPrefix = hostNameIpPrefixMap[host];

                long long executeStartTimeInMs = [[NSDate date] timeIntervalSince1970] * 1000;
                HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:host byIpType:HttpdnsQueryIPTypeIpv4];
                long long executeEndTimeInMs = [[NSDate date] timeIntervalSince1970] * 1000;
                // 非阻塞接口任何情况下不应该阻塞超过20ms
                if (executeEndTimeInMs - executeStartTimeInMs >= 20) {
                    printf("XCTAssertWillFailed, host: %s, executeTime: %lldms\n", [host UTF8String], executeEndTimeInMs - executeStartTimeInMs);
                }
                XCTAssertLessThan(executeEndTimeInMs - executeStartTimeInMs, 20);
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
