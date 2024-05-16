//
//  HttpdnsHostRecord.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsHostRecord.h"
#import "HttpdnsUtil.h"

@interface HttpdnsHostRecord()

@property (nonatomic, assign) NSUInteger hostRecordId;

/*!
 * 域名
 */
@property (nonatomic, copy) NSString *host;

/*!
 * 运营商
 */
@property (nonatomic, copy) NSString *carrier;

/*!
 * 查询时间，单位是秒。
 */
@property (nonatomic, strong) NSDate *createAt;

@property (nonatomic, strong) NSDate *expireAt;

/*!
 * IP列表
 */
@property (nonatomic, copy) NSArray<NSString *> *IPs;

/*!
 * TTL
 */
@property (nonatomic, assign) int64_t TTL;


/*!
 * ipRegion 数据库字段 当次解析ipv4服务IP region
 */
@property (nonatomic, copy) NSString *ipRegion;

/*!
 * ip6Region 数据库字段 当次解析ipv6服务IP region
 */
@property (nonatomic, copy) NSString *ip6Region;

@end

@implementation HttpdnsHostRecord

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
                 ip6Region:(NSString *)ip6Region {
    if (self = [super init]) {
        _hostRecordId = hostRecordId;
        _host = [host copy];
        _carrier = [carrier copy];
        _IPs = [IPs copy];
        _IP6s = [IP6s copy];
        _TTL = TTL;
        _createAt = createAt;
        _expireAt = expireAt;
        _ipRegion = ipRegion;
        _ip6Region = ip6Region;
    }
    return self;
}

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
                       ip6Region:(NSString *)ip6Region
{
    HttpdnsHostRecord *hostRecord = [[HttpdnsHostRecord alloc] initWithId:hostRecordId
                                                                     host:host
                                                                  carrier:carrier
                                                                      IPs:IPs
                                                                     IP6s:IP6s
                                                                      TTL:TTL
                                                                 createAt:createAt expireAt:expireAt ipRegion:ipRegion ip6Region:ip6Region];
    return hostRecord;
}

/*!
 * 从网络初始化
 */
- (instancetype)initWithHost:(NSString *)host
                         IPs:(NSArray<NSString *> *)IPs
                        IP6s:(NSArray<NSString *> *)IP6s
                         TTL:(int64_t)TTL
                    ipRegion:(NSString *)ipRegion
                   ip6Region:(NSString *)ip6Region {
    if (self = [super init]) {
        _host = [host copy];
        _IPs = [IPs copy];
        _IP6s = [IP6s copy];
        _TTL = TTL;
        _ipRegion = ipRegion;
        _ip6Region = ip6Region;
    }
    return self;
}

/*!
 * 从网络初始化
 */
+ (instancetype)hostRecordWithHost:(NSString *)host
                               IPs:(NSArray<NSString *> *)IPs
                              IP6s:(NSArray<NSString *> *)IP6s
                               TTL:(int64_t)TTL
                          ipRegion:(NSString *)ipRegion
                         ip6Region:(NSString *)ip6Region {
    HttpdnsHostRecord *hostRecord = [[HttpdnsHostRecord alloc] initWithHost:host IPs:IPs IP6s:IP6s TTL:TTL ipRegion:ipRegion ip6Region:ip6Region];
    return hostRecord;
}

/*!
 * 从网络初始化
 */
- (instancetype)initWithHostSdns:(NSString *)host
                             IPs:(NSArray<NSString *> *)IPs
                            IP6s:(NSArray<NSString *> *)IP6s
                             TTL:(int64_t)TTL
                           Extra:(NSDictionary *)extra
                        ipRegion:(NSString *)ipRegion
                       ip6Region:(NSString *)ip6Region {
    if (self = [super init]) {
        _host = [host copy];
        _IPs = [IPs copy];
        _IP6s = [IP6s copy];
        _TTL = TTL;
        _extra = extra;
        _ipRegion = ipRegion;
        _ip6Region = ip6Region;
    }
    return self;
}

/*!
 * 从网络初始化
 */
+ (instancetype)sdnsHostRecordWithHost:(NSString *)host
                                   IPs:(NSArray<NSString *> *)IPs
                                  IP6s:(NSArray<NSString *> *)IP6s
                                   TTL:(int64_t)TTL
                                 Extra:(NSDictionary *)extra
                              ipRegion:(NSString *)ipRegion
                             ip6Region:(NSString *)ip6Region{
    HttpdnsHostRecord *hostRecord = [[HttpdnsHostRecord alloc] initWithHostSdns:host IPs:IPs IP6s:IP6s TTL:TTL Extra:extra ipRegion:ipRegion ip6Region:ipRegion];
    return hostRecord;
}


- (NSString *)description {
    NSString *des;
    if (![HttpdnsUtil isValidArray:_IP6s]) {
        des = [NSString stringWithFormat:@"hostRecordId = %@, host = %@, carrier = %@, IPs = %@ , TTL = %@---",
               @(_hostRecordId), _host, _carrier, _IPs, @(_TTL)];
    } else {
        des = [NSString stringWithFormat:@"hostRecordId = %@, host = %@, carrier = %@, IPs = %@ , IP6s = %@, TTL = %@---",
               @(_hostRecordId), _host, _carrier, _IPs, _IP6s, @(_TTL)];
    }
    return des;
}

@end
