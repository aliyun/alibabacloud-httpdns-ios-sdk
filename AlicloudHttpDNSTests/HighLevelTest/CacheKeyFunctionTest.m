//
//  CacheKeyFunctionTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/6/12.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsRequestScheduler_Internal.h"
#import "TestBase.h"

@interface CacheKeyFunctionTest : TestBase

@end

static int ttlForTest = 120;
static NSString *sdnsHost = @"sdns1.onlyforhttpdnstest.run.place";

@implementation CacheKeyFunctionTest

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
    [self.httpdns setPersistentCacheIPEnabled:YES];
    [self.httpdns setReuseExpiredIPEnabled:NO];

    [self.httpdns setLogHandler:self];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (void)testSimpleSpecifyingCacheKeySituation {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSString *testHost = hostNameIpPrefixMap.allKeys.firstObject;
    NSString *cacheKey = [NSString stringWithFormat:@"cacheKey-%@", testHost];
    __block NSString *ipPrefix = hostNameIpPrefixMap[testHost];

    // 使用正常解析到的ttl
    [self.httpdns setTtlDelegate:nil];

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeIpv4 withSdnsParams:nil sdnsCacheKey:cacheKey];
        XCTAssertNotNil(result);
        XCTAssertTrue([result.host isEqualToString:testHost]);
        XCTAssertGreaterThan(result.ttl, 0);
        // 同步接口，不复用过期ip的情况下，解析出的ip一定是未过期的
        XCTAssertLessThan([[NSDate date] timeIntervalSince1970], result.lastUpdatedTimeInterval + result.ttl);
        NSString *firstIp = [result firstIpv4Address];
        if (![firstIp hasPrefix:ipPrefix]) {
            printf("XCTAssertWillFailed, host: %s, firstIp: %s, ipPrefix: %s\n", [testHost UTF8String], [firstIp UTF8String], [ipPrefix UTF8String]);
        }
        XCTAssertTrue([firstIp hasPrefix:ipPrefix]);
        dispatch_semaphore_signal(semaphore);
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    [NSThread sleepForTimeInterval:3];

    // 清空缓存
    [self.httpdns.requestScheduler cleanAllHostMemoryCache];

    // 从db再加载到缓存中
    [self.httpdns.requestScheduler syncReloadCacheFromDbToMemoryByIspCarrier];

    HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:testHost byIpType:HttpdnsQueryIPTypeIpv4];
    // 没有使用cacheKey，所以这里应该是nil
    XCTAssertNil(result);

    result = [self.httpdns resolveHostSyncNonBlocking:testHost byIpType:HttpdnsQueryIPTypeIpv4 withSdnsParams:nil sdnsCacheKey:cacheKey];
    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:testHost]);
    NSString *firstIp = [result firstIpv4Address];
    XCTAssertTrue([firstIp hasPrefix:ipPrefix]);
}

@end
