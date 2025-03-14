//
//  ScheduleCenterV6Test.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/6/17.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>
#import "HttpdnsIpv6Adapter.h"
#import "TestBase.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsScheduleCenterRequest.h"
#import "HttpdnsScheduleCenter.h"
#import "HttpdnsScheduleCenter_Internal.h"
#import "HttpdnsService.h"
#import "HttpdnsService_Internal.h"


/**
 * 由于使用OCMock在连续的测试用例中重复Mock对象(即使每次都已经stopMocking)会有内存错乱的问题，
 * 目前还解决不了，所以这个类中的测试case，需要手动单独执行
 */
@interface ScheduleCenterV6Test : TestBase

@end


@implementation ScheduleCenterV6Test

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
    [self presetNetworkEnvAsIpv6];

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

    // 指定已经重试2次，避免重试影响计算
    [scheduleCenter asyncUpdateRegionScheduleConfigAtRetry:2];
    [NSThread sleepForTimeInterval:0.1];

    NSString *activeUpdateHost = [scheduleCenter getActiveUpdateServerHost];

    // 因为可能是域名，所以只判断一定不是ipv4
    XCTAssertFalse([HttpdnsIPv6Adapter isIPv4Address:activeUpdateHost]);

    OCMVerify([mockRequest fetchRegionConfigFromServer:[OCMArg any] error:(NSError * __autoreleasing *)[OCMArg anyPointer]]);

    [NSThread sleepForTimeInterval:3];
}

@end
