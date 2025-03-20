//
//  HttpdnsLoggerProtocol.h
//  AlicloudHttpDNS
//
//  Created by junmo on 2018/12/19.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#ifndef HttpdnsLoggerProtocol_h
#define HttpdnsLoggerProtocol_h

#import <Foundation/Foundation.h>

@protocol HttpdnsLoggerProtocol <NSObject>

- (void)log:(NSString *)logStr;

@end

#endif /* HttpdnsLoggerProtocol_h */
