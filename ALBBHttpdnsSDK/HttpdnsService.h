//
//  Dpa_Httpdns_iOS.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsRequestScheduler.h"

@interface HttpDnsService: NSObject

@property (nonatomic, strong) HttpdnsRequestScheduler *requestScheduler;

+(instancetype)sharedInstance;

// 添加预解析域名
-(void)setPreResolveHosts:(NSArray *)hosts;

// 根据域名查询ip
-(NSString *)getIpByHost:(NSString *)host;
@end
