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
 * 关联host的id，对应于 IPRecord 数据库表内的同名字段。
 */
@property (nonatomic, assign, readonly) NSUInteger hostRecordId;

/*!
 * 解析的IP，对应于 IPRecord 数据库表内的同名字段。
 */
@property (nonatomic, copy, readonly) NSString *IP;

/*!
 * TTL，对应于 IPRecord 数据库表内的同名字段。
 */
@property (nonatomic, assign, readonly) int64_t TTL;

/*!
 * 当次解析IP 的服务IP对应的region
 */
@property (nonatomic, copy, readonly) NSString *region;


/*!
 * 从数据库初始化
 */
- (instancetype)initWithHostRecordId:(NSUInteger)hostRecordId IP:(NSString *)IP TTL:(int64_t)TTL region:(NSString *)region;

/*!
 * 从数据库初始化
 */
+ (instancetype)IPRecordWithHostRecordId:(NSUInteger)hostRecordId IP:(NSString *)IP TTL:(int64_t)TTL region:(NSString *)region;

///*!
// * 从网络初始化
// */
//- (instancetype)initWithIP:(NSString *)IP;
//
///*!
// * 从网络初始化
// */
//+ (instancetype)IPRecordWithIP:(NSString *)IP;

@end
