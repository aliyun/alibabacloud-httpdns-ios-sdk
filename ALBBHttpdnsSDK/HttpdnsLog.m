//
//  HttpdnsLog.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/2/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsLog.h"


BOOL HttpdnsLogIsEnable = NO;

@implementation HttpdnsLog

+ (void)enbaleLog {
    HttpdnsLogIsEnable = YES;
}

+ (void)disableLog {
    HttpdnsLogIsEnable = YES;
}

+ (BOOL)isEnable {
    return HttpdnsLogIsEnable;
}

@end
