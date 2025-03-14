//
//  CustomTTLAndCleanCacheTest.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/6/17.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import <mach/mach.h>
#import "HttpdnsService.h"
#import "HttpdnsHostResolver.h"
#import "TestBase.h"

static int TEST_CUSTOM_TTL_SECOND = 3;

@interface CustomTTLAndCleanCacheTest : TestBase<HttpdnsTTLDelegate>

@end


@implementation CustomTTLAndCleanCacheTest

- (void)setUp {
    [super setUp];

    self.httpdns = [[HttpDnsService alloc] initWithAccountID:100000];
    [self.httpdns setLogEnabled:YES];

    [self.httpdns setTtlDelegate:self];
    [self.httpdns setLogHandler:self];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (void)tearDown {
    [super tearDown];
}

- (int64_t)httpdnsHost:(NSString *)host ipType:(AlicloudHttpDNS_IPType)ipType ttl:(int64_t)ttl {
    // 为了在并发测试中域名快速过期，将ttl设置为3秒
    NSString *testHost = hostNameIpPrefixMap.allKeys.firstObject;
    if ([host isEqual:testHost]) {
        return TEST_CUSTOM_TTL_SECOND;
    }

    return ttl;
}

- (void)testCustomTTL {
    [self presetNetworkEnvAsIpv4];
    [self.httpdns cleanAllHostCache];

    NSString *testHost = hostNameIpPrefixMap.allKeys.firstObject;
    NSString *expectedIpPrefix = hostNameIpPrefixMap[testHost];

    HttpdnsHostResolver *resolver = [HttpdnsHostResolver new];
    id mockResolver = OCMPartialMock(resolver);
    __block int invokeCount = 0;
    OCMStub([mockResolver lookupHostFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]])
        .andDo(^(NSInvocation *invocation) {
            invokeCount++;
        })
        .andForwardToRealObject();

    id mockResolverClass = OCMClassMock([HttpdnsHostResolver class]);
    OCMStub([mockResolverClass new]).andReturn(mockResolver);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, TEST_CUSTOM_TTL_SECOND);
        XCTAssertTrue([result.firstIpv4Address hasPrefix:expectedIpPrefix]);
        XCTAssertEqual(invokeCount, 1);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, TEST_CUSTOM_TTL_SECOND);
        XCTAssertTrue([result.firstIpv4Address hasPrefix:expectedIpPrefix]);
        XCTAssertEqual(invokeCount, 1);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    [NSThread sleepForTimeInterval:TEST_CUSTOM_TTL_SECOND + 1];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, TEST_CUSTOM_TTL_SECOND);
        XCTAssertTrue([result.firstIpv4Address hasPrefix:expectedIpPrefix]);
        XCTAssertEqual(invokeCount, 2);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

@end
