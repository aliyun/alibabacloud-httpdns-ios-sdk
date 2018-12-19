//
//  MyLoggerHandler.m
//  AlicloudHttpDNSTestDemo
//
//  Created by junmo on 2018/12/19.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import "MyLoggerHandler.h"

@implementation MyLoggerHandler

- (void)log:(NSString *)logStr {
    NSLog(@"[myLog] - %@", logStr);
}

@end
