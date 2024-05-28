//
//  EnableReuseExpiredIpTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/5/28.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TestBase.h"

@interface EnableReuseExpiredIpTest : TestBase <HttpdnsTTLDelegate>

@end

static int ttlForTest = 3;

@implementation EnableReuseExpiredIpTest

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

    [self.httpdns setReuseExpiredIPEnabled:YES];

    [self.httpdns setTtlDelegate:self];
    [self.httpdns setLogHandler:self];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (int64_t)httpdnsHost:(NSString *)host ipType:(AlicloudHttpDNS_IPType)ipType ttl:(int64_t)ttl {
    // 在测试中域名快速过期
    return ttlForTest;
}

- (void)testReuseExpiredIp {
    NSString *host = hostNameIpPrefixMap.allKeys.firstObject;
    NSString *ipPrefix = hostNameIpPrefixMap[host];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // 清空缓存
        [self.httpdns.requestScheduler cleanAllHostMemoryCache];

        // 首次解析
        HttpdnsResult *result = [self.httpdns resolveHostSync:host byIpType:HttpdnsQueryIPTypeIpv4];
        XCTAssertNotNil(result);
        XCTAssertTrue([result.host isEqualToString:host]);
        XCTAssertGreaterThan(result.ttl, 0);
        XCTAssertLessThanOrEqual(result.ttl, ttlForTest);
        XCTAssertLessThan([[NSDate date] timeIntervalSince1970], result.lastUpdatedTimeInterval + result.ttl);
        NSString *firstIp = [result firstIpv4Address];
        XCTAssertTrue([firstIp hasPrefix:ipPrefix]);

        // 等待过期
        [NSThread sleepForTimeInterval:ttlForTest + 1];

        // 重复解析
        HttpdnsResult *result2 = [self.httpdns resolveHostSync:host byIpType:HttpdnsQueryIPTypeIpv4];
        XCTAssertNotNil(result2);
        XCTAssertTrue([result2.host isEqualToString:host]);
        XCTAssertGreaterThan(result2.ttl, 0);
        XCTAssertLessThanOrEqual(result2.ttl, ttlForTest);
        // 因为运行复用过期解析结果，因此这里获得的一定是已经过期的
        XCTAssertGreaterThan([[NSDate date] timeIntervalSince1970], result2.lastUpdatedTimeInterval + result2.ttl);
        NSString *firstIp2 = [result2 firstIpv4Address];
        XCTAssertTrue([firstIp2 hasPrefix:ipPrefix]);

        // 等待第二次解析触发的请求完成
        [NSThread sleepForTimeInterval:1];

        // 再次使用nonblocking方法解析，此时应该已经拿到有效结果
        HttpdnsResult *result3 = [self.httpdns resolveHostSyncNonBlocking:host byIpType:HttpdnsQueryIPTypeIpv4];
        XCTAssertNotNil(result3);
        XCTAssertTrue([result3.host isEqualToString:host]);
        XCTAssertGreaterThan(result3.ttl, 0);
        XCTAssertLessThanOrEqual(result3.ttl, ttlForTest);
        // 有效结果必定未过期
        XCTAssertLessThan([[NSDate date] timeIntervalSince1970], result3.lastUpdatedTimeInterval + result3.ttl);
        NSString *firstIp3 = [result3 firstIpv4Address];
        XCTAssertTrue([firstIp3 hasPrefix:ipPrefix]);

        dispatch_semaphore_signal(semaphore);
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

@end
