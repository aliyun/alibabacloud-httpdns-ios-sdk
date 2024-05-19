//
//  HttpdnsResult.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/5/15.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsResult.h"

@implementation HttpdnsResult

- (BOOL)hasIpv4Address {
    return self.ips.count > 0;
}

- (BOOL)hasIpv6Address {
    return self.ipv6s.count > 0;
}

- (NSString *)firstIpv4Address {
    if (self.ips.count == 0) {
        return nil;
    }
    return self.ips.firstObject;
}

- (NSString *)firstIpv6Address {
    if (self.ipv6s.count == 0) {
        return nil;
    }
    return self.ipv6s.firstObject;
}

- (NSString *)description {
    NSMutableString *result = [NSMutableString stringWithFormat:@"Host: %@", self.host];

    if ([self hasIpv4Address]) {
        [result appendFormat:@", ipv4 Addresses: %@", [self.ips componentsJoinedByString:@", "]];
    } else {
        [result appendString:@", ipv4 Addresses: None"];
    }

    if ([self hasIpv6Address]) {
        [result appendFormat:@", ipv6 Addresses: %@", [self.ipv6s componentsJoinedByString:@", "]];
    } else {
        [result appendString:@", ipv6 Addresses: None"];
    }

    return [result copy];
}

@end
