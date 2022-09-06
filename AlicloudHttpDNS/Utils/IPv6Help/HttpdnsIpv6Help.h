//
//  HttpdnsIpv6Help.h
//  AlicloudHttpDNS
//
//  Created by yannan on 2022/9/6.
//  Copyright © 2022 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>


/**
 * IP 协议栈类型
 */
typedef enum {
    kHttpdnsIPUnkown     = 0,    // 未知协议栈
    kHttpdnsIPv4only     = 1,    // IPv4-only
    kHttpdnsIPv6only     = 2,    // IPv6-only
    kHttpdnsIPdual       = 3     // 双栈
} HttpdnsIPStackType;


NS_ASSUME_NONNULL_BEGIN

@interface HttpdnsIpv6Help : NSObject

+ (instancetype)sharedInstance;

- (BOOL)isIPv6only;

- (HttpdnsIPStackType)currentIpStackType;

- (void)reset;
@end

NS_ASSUME_NONNULL_END
