//
//  HttpdnsIPRecord.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HttpdnsIPRecord : NSObject

/*!
 * 自增id
 */
@property (nonatomic, assign) NSUInteger *id_p;

/*!
 * 关联host的id
 */
@property (nonatomic, assign) NSUInteger *host_id;

/*!
 * 解析的IP
 */
@property (nonatomic, copy) NSString *IP;

/*!
 * TTL
 */
@property (nonatomic, copy) NSString *TTL;

@end
