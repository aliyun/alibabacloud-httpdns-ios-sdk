//
//  HttpdnsRequestTest.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/2/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TestIncludeAllHeader.h"
#import "HttpdnsLog.h"

@interface HttpdnsRequestTest : XCTestCase

@end

@implementation HttpdnsRequestTest

- (void)setUp {
    [super setUp];
    [HttpdnsLog enbaleLog];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testRequestOneHost {
    sleep(1);
    NSString *hostName = @"www.taobao.com";
    HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
    NSError *error;
    NSMutableArray *result = [request lookupAllHostsFromServer:hostName error:&error];
    XCTAssertNil(error, @"error!");
    XCTAssertNotNil(result, @"result is nil!!");
}

- (void)testExample {
    // This is an example of a functional test case.
    XCTAssert(YES, @"Pass");
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end
