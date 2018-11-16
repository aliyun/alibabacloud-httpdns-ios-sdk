//
//  IPv6ResTests.m
//  AlicloudHttpDNSTests
//
//  Created by junmo on 2018/11/16.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import <XCTest/XCTest.h>

@interface IPv6ResTests : XCTestCase

@end

@implementation IPv6ResTests

+ (void)initialize {
    HttpDnsService *httpdns = [[HttpDnsService alloc] initWithAccountID:102933];
    [httpdns setLogEnabled:YES];
}

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

@end
