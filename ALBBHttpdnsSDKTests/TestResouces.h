//
//  TestResouces.h
//  ALBBHttpdnsSDK
//
//  Created by zhouzhuo on 7/10/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#ifndef TEST_RESOURCES_H
#define TEST_RESOURCES_H

#import <Foundation/Foundation.h>
#import "TestIncludeAllHeader.h"

@interface TestResouces : NSObject

+(HttpdnsHostObject *)buildAnHostObjectWithHostName:(NSString *)hostName
                                            withTTL:(int)ttl
                                             withIp:(NSString *)ip
                                     withLookupTime:(long long)lookupTime
                                          withState:(HostState)state;
@end

#endif