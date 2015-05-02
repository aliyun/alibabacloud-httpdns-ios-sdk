//
//  HttpdnsLog.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/2/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

static BOOL isEnable = false;

@interface HttpdnsLog : NSObject

+ (void)enbaleLog;

+ (void)disableLog;

+ (void)LogE:(NSString *)format, ...;

+ (void)LogD:(NSString *)format, ...;

+ (void)LogW:(NSString *)format, ...;
@end
