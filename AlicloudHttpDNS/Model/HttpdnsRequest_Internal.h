//
//  HttpdnsRequest_Internal.h
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/6/19.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#ifndef HttpdnsRequest_Internal_h
#define HttpdnsRequest_Internal_h


@interface HttpdnsRequest ()

@property (nonatomic, assign) BOOL isBlockingRequest;

- (void)setAsBlockingRequest;

- (void)setAsNonBlockingRequest;

- (void)ensureResolveTimeoutInReasonableRange;

@end

#endif /* HttpdnsRequest_Internal_h */
