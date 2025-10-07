//
//  DemoResolveModel.m
//  AlicloudHttpDNSTestDemo
//
//  @author Created by Claude Code on 2025-10-05
//

#import "DemoResolveModel.h"

@implementation DemoResolveModel

- (instancetype)init {
    if (self = [super init]) {
        _host = @"www.aliyun.com";
        _ipType = HttpdnsQueryIPTypeBoth;
        _ipv4s = @[];
        _ipv6s = @[];
        _elapsedMs = 0;
        _ttlV4 = 0;
        _ttlV6 = 0;
    }
    return self;
}

- (void)updateWithResult:(HttpdnsResult *)result startTimeMs:(NSTimeInterval)startMs {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970] * 1000.0;
    _elapsedMs = MAX(0, now - startMs);
    if (result != nil) {
        _ipv4s = result.ips ?: @[];
        _ipv6s = result.ipv6s ?: @[];
        _ttlV4 = result.ttl;
        _ttlV6 = result.v6ttl;
    } else {
        _ipv4s = @[];
        _ipv6s = @[];
        _ttlV4 = 0;
        _ttlV6 = 0;
    }
}

@end

