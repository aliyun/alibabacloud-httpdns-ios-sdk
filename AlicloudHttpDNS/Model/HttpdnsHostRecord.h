//
//  HttpdnsHostRecord.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
//#import "HttpdnsIPRecord.h"

/**
 * 返回值：
 {  host: "www.fake.com",
    ips:[],
    ttl: 300
 }
 */
@interface HttpdnsHostRecord : NSObject

/*!
 * 自增id
 */
@property (nonatomic, assign, readonly) NSUInteger hostRecordId;

/*!
 * 域名
 */
@property (nonatomic, copy, readonly) NSString *host;

/*!
 * 运营商
 */
@property (nonatomic, copy, readonly) NSString *carrier;

/*!
 * 查询时间，单位是秒。
 */
@property (nonatomic, strong, readonly) NSDate *createAt;

/*!
 * 过期时间
 */
@property (nonatomic, strong, readonly) NSDate *expireAt;
/*!
 * IP列表
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *IPs;

/*!
 * TTL
 */
@property (nonatomic, assign, readonly) int64_t TTL;

/*!
 * 从数据库读取数据后，初始化
 */
- (instancetype)initWithId:(NSUInteger)hostRecordId
                      host:(NSString *)host
                   carrier:(NSString *)carrier
                       IPs:(NSArray<NSString *> *)IPs
                       TTL:(int64_t)TTL
                  createAt:(NSDate *)createAt
                  expireAt:(NSDate *)expireAt;

/*!
 * 从数据库读取数据后，初始化
 */
+ (instancetype)hostRecordWithId:(NSUInteger)hostRecordId
                            host:(NSString *)host
                         carrier:(NSString *)carrier
                             IPs:(NSArray<NSString *> *)IPs
                             TTL:(int64_t)TTL
                        createAt:(NSDate *)createAt
                        expireAt:(NSDate *)expireAt;
/*!
 * 从网络初始化
 */
- (instancetype)initWithHost:(NSString *)host
                         IPs:(NSArray<NSString *> *)IPs
                         TTL:(int64_t)TTL;
/*!
 * 从网络初始化
 */
+ (instancetype)hostRecordWithHost:(NSString *)host
                               IPs:(NSArray<NSString *> *)IPs
                               TTL:(int64_t)TTL;

@end
