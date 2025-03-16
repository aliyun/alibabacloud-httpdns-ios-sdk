//
//  SdnsScenarioTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/5/29.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TestBase.h"


@interface SdnsScenarioTest : TestBase <HttpdnsTTLDelegate>

@end

static int ttlForTest = 3;
static NSString *sdnsHost = @"sdns1.onlyforhttpdnstest.run.place";

@implementation SdnsScenarioTest

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

    [self.httpdns setReuseExpiredIPEnabled:NO];

    [self.httpdns setTtlDelegate:self];
    [self.httpdns setLogHandler:self];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (int64_t)httpdnsHost:(NSString *)host ipType:(AlicloudHttpDNS_IPType)ipType ttl:(int64_t)ttl {
    // 在测试中域名快速过期
    return ttlForTest;
}

- (void)testSimpleSdnsScenario {
    NSDictionary *extras = @{
        @"testKey": @"testValue",
        @"key2": @"value2",
        @"key3": @"value3"
    };

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:sdnsHost byIpType:HttpdnsQueryIPTypeIpv4 withSdnsParams:extras sdnsCacheKey:nil];
        XCTAssertNotNil(result);
        XCTAssertNotNil(result.ips);
        // 0.0.0.0 是FC函数上添加进去的
        XCTAssertTrue([result.ips containsObject:@"0.0.0.0"]);

        dispatch_semaphore_signal(semaphore);
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testSdnsScenarioUsingCustomCacheKey {
    [self.httpdns.requestManager cleanAllHostMemoryCache];

    NSDictionary *extras = @{
        @"testKey": @"testValue",
        @"key2": @"value2",
        @"key3": @"value3"
    };

    NSString *cacheKey = [NSString stringWithFormat:@"abcd_%@", sdnsHost];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:sdnsHost byIpType:HttpdnsQueryIPTypeIpv4 withSdnsParams:extras sdnsCacheKey:cacheKey];
        XCTAssertNotNil(result);
        XCTAssertNotNil(result.ips);
        // 0.0.0.0 是FC函数上添加进去的
        XCTAssertTrue([result.ips containsObject:@"0.0.0.0"]);

        dispatch_semaphore_signal(semaphore);
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    // 按预期，上面的结果是按cacheKey来缓存的，这里不指定cacheKey，应当拿到nil
    HttpdnsResult *result1 = [self.httpdns resolveHostSyncNonBlocking:sdnsHost byIpType:HttpdnsQueryIPTypeIpv4];
    XCTAssertNil(result1);

    // 使用cachekey，应立即拿到缓存里的结果
    HttpdnsResult *result2 = [self.httpdns resolveHostSync:sdnsHost byIpType:HttpdnsQueryIPTypeIpv4 withSdnsParams:@{} sdnsCacheKey:cacheKey];
    XCTAssertNotNil(result2);
    XCTAssertNotNil(result2.ips);
    // 0.0.0.0 是FC函数上添加进去的
    XCTAssertTrue([result2.ips containsObject:@"0.0.0.0"]);
}

@end
