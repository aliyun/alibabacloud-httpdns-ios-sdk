//
//  HttpdnsCFHttpWrapper.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/10/22.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HttpdnsCFHttpWrapper : NSObject

- (void)sendHTTPRequestWithURL:(NSURL *)url
                timeoutInterval:(NSTimeInterval)timeoutInterval
                    completion:(void (^)(NSData *data, NSError *error))completion;


@end

NS_ASSUME_NONNULL_END
