//
//  HttpdnsIPRecord.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HttpdnsIPRecord : NSObject

/*!
 * 自增id
 */
//@property (nonatomic, assign) NSUInteger IPRecordId;

/*!
 * 关联host的id
 */
@property (nonatomic, assign, readonly) NSUInteger hostRecordId;

/*!
 * 解析的IP
 */
@property (nonatomic, copy, readonly) NSString *IP;

/*!
 * TTL
 */
@property (nonatomic, assign, readonly) int64_t TTL;
/*!
 * 从数据库初始化
 */
- (instancetype)initWithHostRecordId:(NSUInteger)hostRecordId IP:(NSString *)IP TTL:(int64_t)TTL;

/*!
 * 从数据库初始化
 */
+ (instancetype)IPRecordWithHostRecordId:(NSUInteger)hostRecordId IP:(NSString *)IP TTL:(int64_t)TTL;

/*!
 * 从网络初始化
 */
- (instancetype)initWithIP:(NSString *)IP;

/*!
 * 从网络初始化
 */
+ (instancetype)IPRecordWithIP:(NSString *)IP;

@end
