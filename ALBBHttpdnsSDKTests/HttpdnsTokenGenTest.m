//
//  HttpdnsTokenGenTest.m
//  ALBBHttpdnsSDK
//
//  Created by zhouzhuo on 5/26/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TestIncludeAllHeader.h"

@interface HttpdnsTokenGenTest : XCTestCase

@end

@implementation HttpdnsTokenGenTest

- (void)setUp {
    [HttpdnsLog enbaleLog];
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testTokenEnvironmentInitialize {
    HttpdnsTokenGen *tokenGen = [HttpdnsTokenGen sharedInstance];
    HttpdnsToken *token = [tokenGen getToken];
    token = [tokenGen getToken];
    sleep(5);
    NSLog(@"token: %@", token);
    XCTAssertNotNil(token, "Didn't get token");
}
@end
