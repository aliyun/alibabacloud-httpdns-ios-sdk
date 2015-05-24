//
//  HttpdnsLocalCacheTest.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/18/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "HttpdnsLocalCache.h"
#import "HttpdnsModel.h"

@interface HttpdnsLocalCacheTest : XCTestCase

@end

@implementation HttpdnsLocalCacheTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testReadAndWriteNormally {
    NSMutableDictionary *managerDict = [[NSMutableDictionary alloc] init];
    HttpdnsHostObject *host = [[HttpdnsHostObject alloc] init];
    [host setHostName:@"www.taobao.com"];
    [managerDict setObject:host forKey:@"www.taobao.com"];
    dispatch_queue_t syncQueue = dispatch_queue_create("com.alibaba.sdk.httpdns", NULL);
    NSMutableDictionary *testDict = [[NSMutableDictionary alloc] init];
    [testDict setObject:@"fdsfd" forKey:@"fdfds"];
    [HttpdnsLocalCache writeToLocalCache:testDict inQueue:syncQueue];
    NSDictionary *dict = [HttpdnsLocalCache readFromLocalCache];
    XCTAssertEqual(1, [dict count], @"Failed");
}

@end
