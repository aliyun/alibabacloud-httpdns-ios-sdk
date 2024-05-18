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
 * 自增id，对应于 HostRecord 数据库表内的同名字段。
 */
@property (nonatomic, assign, readonly) NSUInteger hostRecordId;

/*!
 * 域名，对应于 HostRecord 数据库表内的同名字段。
 */
@property (nonatomic, copy, readonly) NSString *host;

/*!
 * 运营商，对应于 HostRecord 数据库表内的同名字段。
 */
@property (nonatomic, copy, readonly) NSString *carrier;

/*!
 * 查询时间，单位是秒，对应于 HostRecord 数据库表内的同名字段。
 */
@property (nonatomic, strong, readonly) NSDate *createAt;

/*!
 * 过期时间，对应于 HostRecord 数据库表内的同名字段。
 */
@property (nonatomic, strong, readonly) NSDate *expireAt;

/*!
 * IP列表，非数据库字段，仅为兼容HttpdnsHostObject进行数据传递。
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *IPs;

/*!
 * IPv6列表，非数据库字段，仅为兼容HttpdnsHostObject进行数据传递。
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *IP6s;

/*!
 * TTL，非数据库字段，仅为兼容HttpdnsHostObject进行数据传递。
 */
@property (nonatomic, assign, readonly) int64_t TTL;

/*!
 * extra，非数据库字段，仅为兼容HttpdnsHostObject进行数据传递。
 */
@property (nonatomic, copy, readonly) NSDictionary *extra;

/*!
 * ipRegion 数据库字段 当次解析ipv4服务IP region
 */
@property (nonatomic, copy, readonly) NSString *ipRegion;

/*!
 * ip6Region 数据库字段 当次解析ipv6服务IP region
 */
@property (nonatomic, copy, readonly) NSString *ip6Region;


/*!
 * 从数据库读取数据后，初始化
 */
- (instancetype)initWithId:(NSUInteger)hostRecordId
                      host:(NSString *)host
                   carrier:(NSString *)carrier
                       IPs:(NSArray<NSString *> *)IPs
                      IP6s:(NSArray<NSString *> *)IP6s
                       TTL:(int64_t)TTL
                  createAt:(NSDate *)createAt
                  expireAt:(NSDate *)expireAt
                  ipRegion:(NSString *)ipRegion
                 ip6Region:(NSString *)ip6Region;

/*!
 * 从数据库读取数据后，初始化
 */
+ (instancetype)hostRecordWithId:(NSUInteger)hostRecordId
                            host:(NSString *)host
                         carrier:(NSString *)carrier
                             IPs:(NSArray<NSString *> *)IPs
                            IP6s:(NSArray<NSString *> *)IP6s
                             TTL:(int64_t)TTL
                        createAt:(NSDate *)createAt
                        expireAt:(NSDate *)expireAt
                        ipRegion:(NSString *)ipRegion
                       ip6Region:(NSString *)ip6Region;
/*!
 * 从网络初始化
 */
- (instancetype)initWithHost:(NSString *)host
                         IPs:(NSArray<NSString *> *)IPs
                        IP6s:(NSArray<NSString *> *)IP6s
                         TTL:(int64_t)TTL
                    ipRegion:(NSString *)ipRegion
                   ip6Region:(NSString *)ip6Region;

/*!
 * 从网络初始化
 */
+ (instancetype)hostRecordWithHost:(NSString *)host
                               IPs:(NSArray<NSString *> *)IPs
                              IP6s:(NSArray<NSString *> *)IP6s
                               TTL:(int64_t)TTL
                          ipRegion:(NSString *)ipRegion
                         ip6Region:(NSString *)ip6Region;

/*!
 * 从网络初始化
 */
- (instancetype)initWithHostSdns:(NSString *)host
                         IPs:(NSArray<NSString *> *)IPs
                        IP6s:(NSArray<NSString *> *)IP6s
                         TTL:(int64_t)TTL
                       Extra:(NSDictionary *)extra
                        ipRegion:(NSString *)ipRegion
                       ip6Region:(NSString *)ip6Region;
/*!
 * 从网络初始化
 */
+ (instancetype)sdnsHostRecordWithHost:(NSString *)host
                               IPs:(NSArray<NSString *> *)IPs
                              IP6s:(NSArray<NSString *> *)IP6s
                               TTL:(int64_t)TTL
                             Extra:(NSDictionary *)extra
                              ipRegion:(NSString *)ipRegion
                             ip6Region:(NSString *)ip6Region;




@end
