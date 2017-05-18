//
//  HttpdnsHostRecord.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsHostRecord.h"

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

@end

@implementation HttpdnsHostRecord

/*!
 * 从数据库读取数据后，初始化
 */
- (instancetype)initWithId:(NSUInteger)hostRecordId
                      host:(NSString *)host
                   carrier:(NSString *)carrier
                       IPs:(NSArray<NSString *> *)IPs
                       TTL:(int64_t)TTL
                  createAt:(NSDate *)createAt
                  expireAt:(NSDate *)expireAt{
    if (self = [super init]) {
        _hostRecordId = hostRecordId;
        _host = [host copy];
        _carrier = [carrier copy];
        _IPs = [IPs copy];
        _TTL = TTL;
        _createAt = createAt;
        _expireAt = expireAt;
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
                             TTL:(int64_t)TTL
                        createAt:(NSDate *)createAt
                        expireAt:(NSDate *)expireAt {
    HttpdnsHostRecord *hostRecord = [[HttpdnsHostRecord alloc] initWithId:hostRecordId
                                                                     host:host
                                                                  carrier:carrier
                                                                      IPs:IPs
                                                                      TTL:TTL
                                                                 createAt:createAt expireAt:expireAt];
    return hostRecord;
}

/*!
 * 从网络初始化
 */
- (instancetype)initWithHost:(NSString *)host
                         IPs:(NSArray<NSString *> *)IPs
                         TTL:(int64_t)TTL {
    if (self = [super init]) {
        _host = [host copy];
        _IPs = [IPs copy];
        _TTL = TTL;
    }
    return self;
}

/*!
 * 从网络初始化
 */
+ (instancetype)hostRecordWithHost:(NSString *)host
                               IPs:(NSArray<NSString *> *)IPs
                               TTL:(int64_t)TTL {
    HttpdnsHostRecord *hostRecord = [[HttpdnsHostRecord alloc] initWithHost:host IPs:IPs TTL:TTL];
    return hostRecord;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"hostRecordId = %@, host = %@, carrier = %@, IPs = %@ , TTL = %@---",
            @(_hostRecordId), _host, _carrier, _IPs, @(_TTL)];
}

@end
