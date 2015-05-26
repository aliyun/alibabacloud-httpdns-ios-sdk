//
//  HttpdnsLog.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/2/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsLog.h"

@implementation HttpdnsLog


+ (void)enbaleLog {
    isEnable = true;
}

+ (void)disableLog {
    isEnable = false;
}

+ (void)LogE:(NSString *)format, ... {
    if (isEnable) {
        va_list ap;
        va_start(ap, format);
        format = [NSString stringWithFormat:@"HttpdnsLog error: %@", format];
        NSLogv(format, ap);
        va_end(ap);
    }
}

+ (void)LogD:(NSString *)format, ... {
    if (isEnable) {
        va_list ap;
        va_start(ap, format);
        format = [NSString stringWithFormat:@"HttpdnsLog debug: %@", format];
        NSLogv(format, ap);
        va_end(ap);
    }
}

+ (void)LogW:(NSString *)format, ... {
    if (isEnable) {
        va_list ap;
        va_start(ap, format);
        format = [NSString stringWithFormat:@"HttpdnsLog warn: %@", format];
        NSLogv(format, ap);
        va_end(ap);
    }
}

@end
