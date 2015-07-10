//
//  HttpdnsServiceTest.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/24/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TestIncludeAllHeader.h"

@interface HttpdnsServiceTest : XCTestCase

@end

@implementation HttpdnsServiceTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)test_getIpByHost {
    [HttpdnsLog enbaleLog];
    sleep(2);
    // [HttpdnsLocalCache cleanLocalCache];
    HttpDnsServiceProvider *dns = [HttpDnsServiceProvider getService];
    NSArray *hosts = [[NSArray alloc] initWithObjects:@"www.taobao.com", @"www.alipay.com", nil];
    [dns setPreResolveHosts:hosts];
    [dns getIpByHost:@"img01.taobaocdn.com"];
}

@end
