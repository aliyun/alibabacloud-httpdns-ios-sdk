//
//  ManuallyCleanCacheTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/6/17.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import <mach/mach.h>
#import "HttpdnsService.h"
#import "HttpdnsRemoteResolver.h"
#import "TestBase.h"

static int TEST_CUSTOM_TTL_SECOND = 3;

@interface ManuallyCleanCacheTest : TestBase

@end


@implementation ManuallyCleanCacheTest

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

- (void)testCleanSingleHost {
    [self presetNetworkEnvAsIpv4];
    [self.httpdns cleanAllHostCache];

    NSString *testHost = ipv4OnlyHost;
    HttpdnsHostObject *hostObject = [self constructSimpleIpv4HostObject];
    hostObject.ttl = 60;
    [hostObject setV4TTL:60];

    HttpdnsRemoteResolver *resolver = [HttpdnsRemoteResolver new];
    id mockResolver = OCMPartialMock(resolver);
    __block int invokeCount = 0;
    OCMStub([mockResolver lookupHostFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]])
        .andDo(^(NSInvocation *invocation) {
            invokeCount++;
        })
        .andReturn(hostObject);

    id mockResolverClass = OCMClassMock([HttpdnsRemoteResolver class]);
    OCMStub([mockResolverClass new]).andReturn(mockResolver);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, 60);
        XCTAssertEqual(invokeCount, 1);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    [self.httpdns cleanHostCache:@[@"invalidhostofcourse"]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, 60);
        XCTAssertEqual(invokeCount, 1);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    [self.httpdns cleanHostCache:@[testHost]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, 60);
        XCTAssertEqual(invokeCount, 2);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testCleanAllHost {
    [self presetNetworkEnvAsIpv4AndIpv6];
    [self.httpdns cleanAllHostCache];

    NSString *testHost = ipv4OnlyHost;
    HttpdnsHostObject *hostObject = [self constructSimpleIpv4HostObject];
    hostObject.ttl = 60;
    [hostObject setV4TTL:60];

    HttpdnsRemoteResolver *resolver = [HttpdnsRemoteResolver new];
    id mockResolver = OCMPartialMock(resolver);
    __block int invokeCount = 0;
    OCMStub([mockResolver lookupHostFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]])
        .andDo(^(NSInvocation *invocation) {
            invokeCount++;
        })
        .andReturn(hostObject);

    id mockResolverClass = OCMClassMock([HttpdnsRemoteResolver class]);
    OCMStub([mockResolverClass new]).andReturn(mockResolver);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, 60);
        XCTAssertEqual(invokeCount, 1);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    [self.httpdns cleanHostCache:@[@"invalidhostofcourse"]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, 60);
        XCTAssertEqual(invokeCount, 1);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    [self.httpdns cleanAllHostCache];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:testHost byIpType:HttpdnsQueryIPTypeAuto];
        XCTAssertNotNil(result);
        XCTAssertEqual(result.ttl, 60);
        XCTAssertEqual(invokeCount, 2);

        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

@end
