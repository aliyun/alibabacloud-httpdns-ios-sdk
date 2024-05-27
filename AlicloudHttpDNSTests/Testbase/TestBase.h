//
//  TestBase.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/14.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AlicloudUtils/AlicloudUtils.h>
#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "XCTestCase+AsyncTesting.h"
#import "HttpdnsRequest.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsService.h"
#import "HttpdnsService_Internal.h"


#define NOTIFY [self notify:XCTAsyncTestCaseStatusSucceeded];
#define WAIT [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:30];
#define WAIT_60 [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:60];
#define WAIT_120 [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:120];
#define WAIT_10 [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:10.0];
#define WAIT_FOREVER [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:DBL_MAX];

static NSString *ipv4OnlyHost = @"ipv4.only.com";
static NSString *ipv6OnlyHost = @"ipv6.only.com";
static NSString *ipv4AndIpv6Host = @"ipv4.and.ipv6.com";

static NSString *ipv41 = @"1.1.1.1";
static NSString *ipv42 = @"2.2.2.2";
static NSString *ipv61 = @"2001:4860:4860::8888";
static NSString *ipv62 = @"2001:4860:4860::8844";

static NSMutableArray *mockedObjects;

@interface TestBase : XCTestCase

@property (nonatomic, assign) NSTimeInterval currentTimeStamp;

- (HttpdnsHostObject *)constructSimpleIpv4HostObject;

- (HttpdnsHostObject *)constructSimpleIpv6HostObject;

- (HttpdnsHostObject *)constructSimpleIpv4AndIpv6HostObject;

- (void)presetNetworkEnvAsIpv4;

- (void)presetNetworkEnvAsIpv6;

- (void)presetNetworkEnvAsIpv4AndIpv6;

- (void)shouldNotHaveCalledRequestWhenResolving:(void (^)(void))resolvingBlock;

- (void)shouldHaveCalledRequestWhenResolving:(void (^)(void))resolvingBlock;

@end
