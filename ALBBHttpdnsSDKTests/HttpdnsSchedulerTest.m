//
//  HttpdnsSchedulerTest.m
//  ALBBHttpdnsSDK
//
//  Created by zhouzhuo on 5/27/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TestIncludeAllHeader.h"

@interface HttpdnsSchedulerTest : XCTestCase

@property (nonatomic, strong) id<ALBBHttpdnsServiceProtocol> httpdns;

@end

static NSString * aliyunHost = @"www.aliyun.com";
@implementation HttpdnsSchedulerTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    _httpdns = [HttpDnsServiceProvider getService];
    [HttpdnsLog enbaleLog];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testMergeResult {
}

@end
