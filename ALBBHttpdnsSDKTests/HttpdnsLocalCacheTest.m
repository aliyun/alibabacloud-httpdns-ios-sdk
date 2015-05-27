//
//  HttpdnsLocalCacheTest.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/18/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TestIncludeAllHeader.h"

@interface HttpdnsLocalCacheTest : XCTestCase

@end

@implementation HttpdnsLocalCacheTest

- (void)setUp {
    [HttpdnsLog enbaleLog];
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testReadAndWriteNormally {
    HttpdnsIpObject *ip = [[HttpdnsIpObject alloc] init];
    [ip setIp:@"223.5.5.5"];
    HttpdnsHostObject *host = [[HttpdnsHostObject alloc] init];
    [host setHostName:@"www.taobao.com"];
    NSMutableDictionary *testDict = [[NSMutableDictionary alloc] init];
    [testDict setObject:host forKey:@"fdfds"];
    [HttpdnsLocalCache writeToLocalCache:testDict];
    NSDictionary *dict = [HttpdnsLocalCache readFromLocalCache];
    XCTAssertEqual(1, [dict count], @"Failed");
}

@end
