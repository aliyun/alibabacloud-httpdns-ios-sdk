//
//  HttpdnsTestUtil.h
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/18/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsModel.h"

@interface HttpdnsTestUtil : NSObject

+(HttpdnsHostObject *)buildAFakeHostObjectWithHostName:(NSString *)hostName;

+(HttpdnsIpObject *)buildAFackIpObject;
@end
