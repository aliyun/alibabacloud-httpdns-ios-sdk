//
//  HttpdnsIPv6Adapter.h
//  AlicloudHttpDNS
//
//  Created by lingkun on 16/5/16.
//  Copyright © 2016年 Ali. All rights reserved.
//

#ifndef HttpdnsIPv6Adapter_h
#define HttpdnsIPv6Adapter_h
#import <Foundation/Foundation.h>

@interface HttpdnsIPv6Adapter : NSObject

+ (instancetype)getInstance;

- (void)updateIPv6Prefix;

- (NSString *)convertIPv4toIPv6:(NSString *)ipv4;

/* For Test */
- (NSString *)convertBySystem:(NSString *)ipv4Addr;
- (void)forceConvertByType:(int)type;
- (BOOL)ipv4OnlyIP:(const __uint8_t *)ip matchPrefixBitsCount:(__uint8_t)count;

@end

#endif /* HttpdnsIPv6Adapter_h */
