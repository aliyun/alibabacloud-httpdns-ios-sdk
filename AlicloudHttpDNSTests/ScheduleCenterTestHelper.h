//
//  HttpdnsScheduleCenterTestHelper.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/13.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ScheduleCenterTestHelper : NSObject

+ (void)setFirstIPWrongForTest;
+ (void)setTwoFirstIPWrongForTest;
+ (void)setFourFirstIPWrongForTest;
+ (void)setFourLastIPWrongForTest;

/*!
 * 恢复正常
 */
+ (void)setAllThreeWrongForTest;
+ (void)resetAllThreeRightForTest;

+ (void)cancelAutoConnectToScheduleCenter;
+ (void)resetAutoConnectToScheduleCenter;

+ (void)setStopService;

/*!
 * 获取SC更新本地文件的时间距离现在有多久，单位是秒
 */
+ (NSTimeInterval)timeSinceCreateForScheduleCenterResult;

@end
