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
 * 获取当前等待队列中的任务数量
 */
- (NSUInteger)pendingTasksCount;

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

#pragma mark - Methods exposed for testing

/**
 * 执行IP连接质量检测
 * @param cacheKey 缓存键，通常是域名
 * @param ip 要检测的IP地址
 * @param port 连接端口，如果为nil则默认使用80
 * @param callback 检测完成后的回调
 * @note 此方法主要用于测试
 */
- (void)executeDetection:(NSString *)cacheKey
                      ip:(NSString *)ip
                    port:(nullable NSNumber *)port
                callback:(HttpdnsIPQualityCallback)callback;

/**
 * 建立TCP连接并测量连接时间
 * @param ip 要连接的IP地址
 * @param port 连接端口
 * @return 连接耗时（毫秒），-1表示连接失败
 * @note 此方法主要用于测试
 */
- (NSInteger)tcpConnectToIP:(NSString *)ip port:(int)port;

/**
 * 添加待处理任务
 * @param cacheKey 缓存键，通常是域名
 * @param ip 要检测的IP地址
 * @param port 连接端口
 * @param callback 检测完成后的回调
 * @note 此方法主要用于测试
 */
- (void)addPendingTask:(NSString *)cacheKey
                    ip:(NSString *)ip
                  port:(nullable NSNumber *)port
              callback:(HttpdnsIPQualityCallback)callback;

/**
 * 处理待处理任务队列
 * @note 此方法主要用于测试
 */
- (void)processPendingTasksIfNeeded;

/**
 * 处理所有待处理任务
 * @note 此方法主要用于测试
 */
- (void)processPendingTasks;

@end

NS_ASSUME_NONNULL_END
