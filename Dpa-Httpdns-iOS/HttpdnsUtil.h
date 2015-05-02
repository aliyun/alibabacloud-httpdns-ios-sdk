//
//  HttpdnsUtil.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HttpdnsUtil : NSObject

+(NSString *)HMACSha1Sign:(NSData *)data withKey:(NSString *)key;

+(long long)currentEpochTimeInSecond;

+(NSString *)currentEpochTimeInSecondString;
@end
