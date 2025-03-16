//
//  HttpdnsIpStackDetector.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/16.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * IP 协议栈类型
 */
typedef enum {
    kHttpdnsIpUnknown     = 0,    // 未知协议栈
    kHttpdnsIpv4Only     = 1,    // IPv4-only
    kHttpdnsIpv6Only     = 2,    // IPv6-only
    kHttpdnsIpDual       = 3     // 双栈
} HttpdnsIPStackType;

@interface HttpdnsIpStackDetector : NSObject

/**
 * 返回HttpdnsIpStackDetector的共享实例
 * @return HttpdnsIpStackDetector实例
 */
+ (instancetype)sharedInstance;

/**
 * 返回当前缓存的IP协议栈类型，不执行检测
 * @return HttpdnsIPStackType
 */
- (HttpdnsIPStackType)currentIpStack;

- (BOOL)isIpv6OnlyNetwork;

/**
 * 强制重新检测IP协议栈类型
 * @return HttpdnsIPStackType - 新检测到的IP协议栈类型
 */
- (HttpdnsIPStackType)redetectIpStack;

@end

NS_ASSUME_NONNULL_END
