//
//  HttpdnsScheduleCenterTestHelper.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/13.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "ScheduleCenterTestHelper.h"
#import "HttpdnsConstants.h"
#import "HttpdnsScheduleCenter_Internal.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsPersistenceUtils.h"

@implementation ScheduleCenterTestHelper

+ (void)cancelAutoConnectToScheduleCenter {
    [[HttpdnsScheduleCenter sharedInstance] setNeedToFetchFromScheduleCenter:NO];
}

+ (void)resetAutoConnectToScheduleCenter {
    [[HttpdnsScheduleCenter sharedInstance] setNeedToFetchFromScheduleCenter:YES];
}


+ (void)setStopService {
    NSDictionary *dictionary = @{
                                 ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_KEY : ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_DISABLE_VALUE
                                 };
    [self resetIPResultWithDict:dictionary];
}

+ (void)setFirstIPWrongForTest {
    NSArray *IPList = @[
                        @"190.190.190.190",
                        ALICLOUD_HTTPDNS_SERVER_IP_1,
                        ALICLOUD_HTTPDNS_SERVER_IP_2,
                        ALICLOUD_HTTPDNS_SERVER_IP_3,
                        ALICLOUD_HTTPDNS_SERVER_IP_4
                        ];
    [self resetIPResultWithIPList:IPList];
}

+ (void)setTwoFirstIPWrongForTest {
    NSArray *IPList = @[
                        @"190.190.190.190",
                        @"191.191.191.191",
                        ALICLOUD_HTTPDNS_SERVER_IP_2,
                        ALICLOUD_HTTPDNS_SERVER_IP_3,
                        ALICLOUD_HTTPDNS_SERVER_IP_4
                        ];
    [self resetIPResultWithIPList:IPList];
}

+ (void)setFourFirstIPWrongForTest {
    NSArray *IPList = @[
                        @"190.190.190.190",
                        @"191.191.191.191",
                        @"192.192.192.192",
                        @"193.193.193.193",
                        ALICLOUD_HTTPDNS_SERVER_IP_4,
                        ];
    [self resetIPResultWithIPList:IPList];
}

+ (void)setFourLastIPWrongForTest {
    NSArray *IPList = @[
                        ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED,
                        @"191.191.191.191",
                        @"192.192.192.192",
                        @"193.193.193.193",
                        @"194.194.194.194",
                        ];
    [self resetIPResultWithIPList:IPList];
}

+ (void)setAllThreeWrongForTest {
    NSArray *IPList = @[
                        @"190.190.190.190",
                        @"191.191.191.191",
                        @"192.192.192.192",
                        ];
    [self resetIPResultWithIPList:IPList];
}

+ (void)resetAllThreeRightForTest {
    @synchronized(self) {
    NSArray *IPList = @[
                        ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED,
                        ALICLOUD_HTTPDNS_SERVER_IP_1,
                        ALICLOUD_HTTPDNS_SERVER_IP_2,
                        ALICLOUD_HTTPDNS_SERVER_IP_3,
                        ALICLOUD_HTTPDNS_SERVER_IP_4
                        ];
    [self resetIPResultWithIPList:IPList];
    }
}

+ (void)resetIPResultWithIPList:(NSArray *)IPList {
    [HttpdnsScheduleCenter sharedInstance].IPList = IPList;
    NSDictionary *dictionary = @{
                                 ALICLOUD_HTTPDNS_SCHEDULE_CENTER_CONFIGURE_SERVICE_IP_KEY : IPList,
                                 };
    [self resetIPResultWithDict:dictionary];
}

+ (void)resetIPResultWithDict:(NSDictionary *)Dict {
    [[HttpdnsScheduleCenter sharedInstance] setScheduleCenterResult:Dict];
}

+ (NSTimeInterval)timeSinceCreateForScheduleCenterResult  {
    NSString *path = [[HttpdnsScheduleCenter sharedInstance] scheduleCenterResultPath];
    return [HttpdnsPersistenceUtils timeSinceCreateForPath:path];
}

@end
