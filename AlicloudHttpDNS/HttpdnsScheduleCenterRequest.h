//
//  HttpdnsScheduleCenterRequest.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/4/11.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HttpdnsScheduleCenterRequest : NSObject

- (NSDictionary *)queryScheduleCenterRecordFromServerSync;

@end
