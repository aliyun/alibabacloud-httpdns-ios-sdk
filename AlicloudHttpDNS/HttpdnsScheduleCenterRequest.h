//
//  HttpdnsScheduleCenterRequest.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/11.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HttpdnsScheduleCenterRequest : NSObject

- (NSDictionary *)fetchRegionConfigFromServer:(NSString *)updateHost error:(NSError **)pError;

@end
