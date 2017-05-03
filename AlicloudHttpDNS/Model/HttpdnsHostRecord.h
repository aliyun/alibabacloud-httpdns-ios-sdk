//
//  HttpdnsHostRecord.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsIPRecord.h"

@interface HttpdnsHostRecord : NSObject

/*!
 * 自增id
 */
@property (nonatomic, assign) NSUInteger *hostRecordId;

/*!
 * 域名
 */
@property (nonatomic, copy) NSString *host;

/*!
 * 运营商
 */
@property (nonatomic, copy) NSString *carrier;

/*!
 * 查询时间
 */
@property (nonatomic, assign) NSUInteger timestamp;

/*!
 * IP列表
 */
@property (nonatomic, copy) NSArray<HttpdnsIPRecord *> *IPs;

@end
