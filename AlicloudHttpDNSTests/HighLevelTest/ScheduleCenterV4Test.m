//
//  ScheduleCenterV4Test.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/6/16.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>
#import "TestBase.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsHostResolver.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsScheduleCenterRequest.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsScheduleCenter_Internal.h"
#import "HttpdnsService.h"
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsRequest_Internal.h"


/**
 * 由于使用OCMock在连续的测试用例中重复Mock对象(即使每次都已经stopMocking)会有内存错乱的问题，
 * 目前还解决不了，所以这个类中的测试case，需要手动单独执行
 */
@interface ScheduleCenterV4Test : TestBase

@end


@implementation ScheduleCenterV4Test

+ (void)setUp {
    [super setUp];
}

+ (void)tearDown {
    [super tearDown];
}

- (void)setUp {
    [super setUp];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        self.httpdns = [[HttpDnsService alloc] initWithAccountID:100000];
    });

    [self.httpdns setLogEnabled:YES];
    [self.httpdns setReuseExpiredIPEnabled:NO];

    [self.httpdns setLogHandler:self];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testUpdateFailureWillMoveToNextUpdateServer {
    [self presetNetworkEnvAsIpv4];

    HttpdnsScheduleCenterRequest *realRequest = [HttpdnsScheduleCenterRequest new];
    id mockRequest = OCMPartialMock(realRequest);
    OCMStub([mockRequest fetchRegionConfigFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]])
        .andReturn(nil);

    id mockRequestClass = OCMClassMock([HttpdnsScheduleCenterRequest class]);
    OCMStub([mockRequestClass new]).andReturn(mockRequest);

    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];

    NSArray<NSString *> *updateServerHostList = [scheduleCenter currentUpdateServerV4HostList];

    int updateServerCount = (int)[updateServerHostList count];
    XCTAssertGreaterThan(updateServerCount, 0);

    int startIndex = [scheduleCenter currentActiveUpdateServerHostIndex];

    // 指定已经重试2次，避免重试影响计算
    [scheduleCenter asyncUpdateRegionScheduleConfigAtRetry:2];
    [NSThread sleepForTimeInterval:0.1];

    OCMVerify([mockRequest fetchRegionConfigFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]]);

    int currentIndex = [scheduleCenter currentActiveUpdateServerHostIndex];
    XCTAssertEqual((startIndex + 1) % updateServerCount, currentIndex);

    for (int i = 0; i < updateServerCount; i++) {
        [scheduleCenter asyncUpdateRegionScheduleConfigAtRetry:2];
        [NSThread sleepForTimeInterval:0.1];
    }

    int finalIndex = [scheduleCenter currentActiveUpdateServerHostIndex];
    XCTAssertEqual(currentIndex, finalIndex % updateServerCount);

    [NSThread sleepForTimeInterval:3];
}

- (void)testResolveFailureWillMoveToNextServiceServer {
    [self presetNetworkEnvAsIpv4];

    id mockResolver = OCMPartialMock([HttpdnsHostResolver new]);
    OCMStub([mockResolver lookupHostFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]])
    .andDo(^(NSInvocation *invocation) {
        NSError *mockError = [NSError errorWithDomain:@"com.example.error" code:123 userInfo:@{NSLocalizedDescriptionKey: @"Mock error"}];
        NSError *__autoreleasing *errorPtr = nil;
        [invocation getArgument:&errorPtr atIndex:3];
        if (errorPtr) {
            *errorPtr = mockError;
        }
    });

    id mockResolverClass = OCMClassMock([HttpdnsHostResolver class]);
    OCMStub([mockResolverClass new]).andReturn(mockResolver);

    HttpdnsScheduleCenter *scheduleCenter = [HttpdnsScheduleCenter sharedInstance];
    int startIndex = [scheduleCenter currentActiveServiceServerHostIndex];
    int serviceServerCount = (int)[scheduleCenter currentServiceServerV4HostList].count;

    HttpdnsRequest *request = [[HttpdnsRequest alloc] initWithHost:@"mock" queryIpType:HttpdnsQueryIPTypeAuto];
    [request setAsBlockingRequest];

    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;

    [scheduler executeRequest:request retryCount:1];

    int secondIndex = [scheduleCenter currentActiveServiceServerHostIndex];

    XCTAssertEqual((startIndex + 1) % serviceServerCount, secondIndex);
}

@end
