//
//  HttpdnsLocalCache.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/2/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsModel.h"

@interface HttpdnsLocalCache : NSObject

+(void)writeToLocalCache:(NSDictionary *)allHostObjectInManagerDict;

+(NSDictionary *)readFromLocalCache;

+(void)cleanLocalCache;
@end