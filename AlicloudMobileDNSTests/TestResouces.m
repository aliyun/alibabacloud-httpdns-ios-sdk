//
//  TestResouces.m
//  ALBBHttpdnsSDK
//
//  Created by zhouzhuo on 7/10/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "TestResouces.h"

@implementation TestResouces

+(HttpdnsHostObject *)buildAnHostObjectWithHostName:(NSString *)hostName
                                            withTTL:(int)ttl
                                             withIp:(NSString *)ip
                                     withLookupTime:(long long)lookupTime
                                          withState:(HostState)state {

    HttpdnsHostObject * hostObject = [[HttpdnsHostObject alloc] init];
    [hostObject setHostName:hostName];
    [hostObject setTTL:ttl];
    [hostObject setLastLookupTime:lookupTime];
    [hostObject setState:state];
    HttpdnsIpObject * ipObject = [[HttpdnsIpObject alloc] init];
    [ipObject setIp:ip];
    [hostObject setIps:[[NSArray alloc] initWithObjects:ipObject, nil]];
    return hostObject;
}
@end
