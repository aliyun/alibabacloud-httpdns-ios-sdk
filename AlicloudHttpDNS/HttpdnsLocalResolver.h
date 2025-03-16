//
//  HttpdnsLocalResolver.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/16.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsRequest.h"
#import "HttpdnsHostObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpdnsLocalResolver : NSObject

+ (instancetype)sharedInstance;

- (HttpdnsHostObject *)resolve:(HttpdnsRequest *)request;

@end

NS_ASSUME_NONNULL_END
