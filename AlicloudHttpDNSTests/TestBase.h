//
//  TestBase.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/4/14.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XCTestCase+AsyncTesting.h"

#define NOTIFY [self notify:XCTAsyncTestCaseStatusSucceeded];
#define WAIT [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:30];
#define WAIT_10 [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:10.0];
#define WAIT_FOREVER [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:DBL_MAX];

@interface TestBase : NSObject

@end
