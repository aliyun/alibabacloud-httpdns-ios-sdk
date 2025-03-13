//
//  HttpdnsIPQualityDetector.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/13.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * IP质量检测回调
 * @param cacheKey 缓存键
 * @param ip IP地址
 * @param costTime 连接耗时（毫秒），-1表示连接失败
 */
typedef void(^HttpdnsIPQualityCallback)(NSString *cacheKey, NSString *ip, NSInteger costTime);

@interface HttpdnsIPQualityDetector : NSObject

/**
 * 单例方法
 */
+ (instancetype)sharedInstance;

/**
 * 最大并发检测数量，默认为10
 */
@property (nonatomic, assign) NSUInteger maxConcurrentDetections;

/**
 * 调度一个IP连接质量检测任务，不会阻塞当前线程
 * @param cacheKey 缓存键，通常是域名
 * @param ip 要检测的IP地址
 * @param port 连接端口，如果为nil则默认使用80
 * @param callback 检测完成后的回调
 */
- (void)scheduleIPQualityDetection:(NSString *)cacheKey
                                ip:(NSString *)ip
                              port:(nullable NSNumber *)port
                          callback:(HttpdnsIPQualityCallback)callback;

@end

NS_ASSUME_NONNULL_END
