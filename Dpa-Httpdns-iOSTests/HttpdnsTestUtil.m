//
//  HttpdnsTestUtil.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/18/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsTestUtil.h"

@implementation HttpdnsTestUtil

+(HttpdnsHostObject *)buildAFakeHostObjectWithHostName:(NSString *)hostName {
    HttpdnsHostObject *host = [[HttpdnsHostObject alloc] init];
    [host setLastLookupTime:[[NSDate alloc] timeIntervalSince1970]];
    [host setTTL:5 * 60];
    [host setState:VALID];
    [host setHostName:hostName];
    [host setIps:[HttpdnsTestUtil buildAFakeIpsArray]];
    return host;
}

+(NSArray *)buildAFakeIpsArray {
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (int i = 0; i < 5; i++) {
        [array addObject:[HttpdnsTestUtil buildAFackIpObject]];
    }
    return array;
}

+(HttpdnsIpObject *)buildAFackIpObject {
    HttpdnsIpObject *ip = [[HttpdnsIpObject alloc] init];
    [ip setIp:@"233.5.5.5"];
    return ip;
}

@end
