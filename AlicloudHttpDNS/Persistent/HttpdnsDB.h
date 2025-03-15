//
//  HttpdnsDB.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/15.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsHostRecord.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * SQLite3数据库操作类，用于持久化存储HttpDNS缓存记录
 */
@interface HttpdnsDB : NSObject

/**
 * 初始化数据库
 * @param accountId 账户ID
 * @return 数据库实例
 */
- (instancetype)initWithAccountId:(NSInteger)accountId;

/**
 * 创建或更新记录
 * @param record 主机记录
 * @return 是否成功
 */
- (BOOL)createOrUpdate:(HttpdnsHostRecord *)record;

/**
 * 根据缓存键查询记录
 * @param cacheKey 缓存键
 * @return 查询到的记录，如果不存在则返回nil
 */
- (nullable HttpdnsHostRecord *)selectByCacheKey:(NSString *)cacheKey;

/**
 * 根据缓存键删除记录
 * @param cacheKey 缓存键
 * @return 是否成功
 */
- (BOOL)deleteByCacheKey:(NSString *)cacheKey;

/**
 * 根据主机名数组批量删除记录
 * @param hostNameArr 主机名数组
 * @return 成功删除的记录数量
 */
- (NSInteger)deleteByHostNameArr:(NSArray<NSString *> *)hostNameArr;

/**
 * 获取所有缓存记录
 * @return 所有缓存记录数组
 */
- (NSArray<HttpdnsHostRecord *> *)getAllRecords;

/**
 * 清理指定时间点已过期的记录
 * @param specifiedTime 指定的时间点（epoch时间）
 * @return 清理的记录数量
 */
- (NSInteger)cleanRecordAlreadExpiredAt:(NSTimeInterval)specifiedTime;

/**
 * 删除所有记录
 * @return 是否成功
 */
- (BOOL)deleteAll;

@end

NS_ASSUME_NONNULL_END
