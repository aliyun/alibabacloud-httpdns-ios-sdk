//
//  HttpDnsLocker.h
//  AlicloudHttpDNS
//
//  Created by 王贇 on 2023/8/16.
//  Copyright © 2023 alibaba-inc.com. All rights reserved.
//

#ifndef HttpDnsLocker_h
#define HttpDnsLocker_h

#import <Foundation/Foundation.h>
#import "HttpdnsIPv6Manager.h"

@interface HttpDnsLocker : NSObject

+ (instancetype)sharedInstance;

- (void)lock:(NSString *)host queryType:(HttpdnsQueryIPType)queryType;

- (void)unlock:(NSString *)host queryType:(HttpdnsQueryIPType)queryType;

@end


#endif /* HttpDnsLocker_h */
