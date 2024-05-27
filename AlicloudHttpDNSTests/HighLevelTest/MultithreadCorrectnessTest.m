//
//  MultithreadCorrectnessTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/5/26.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsService.h"
#import "TestBase.h"

@interface MultithreadCorrectnessTest : TestBase

@property (nonatomic, assign) NSTimeInterval currentTimeStamp;

@property (nonatomic, strong) HttpDnsService *httpdns;

@end


static NSMutableArray *mockedObjects;

@implementation MultithreadCorrectnessTest

- (void)setUp {
    [super setUp];

    mockedObjects = [NSMutableArray array];

    self.httpdns = [[HttpDnsService alloc] initWithAccountID:10000];
    [self.httpdns setLogEnabled:YES];
    [self.httpdns setIPv6Enabled:YES];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (void)tearDown {
    [super tearDown];
}

@end
