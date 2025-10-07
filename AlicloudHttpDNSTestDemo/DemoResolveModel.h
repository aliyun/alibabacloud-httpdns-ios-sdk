//
//  DemoResolveModel.h
//  AlicloudHttpDNSTestDemo
//
//  @author Created by Claude Code on 2025-10-05
//

#import <Foundation/Foundation.h>
#import "HttpdnsRequest.h"
#import "HttpdnsResult.h"

@interface DemoResolveModel : NSObject

@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) HttpdnsQueryIPType ipType;

@property (nonatomic, copy) NSArray<NSString *> *ipv4s;
@property (nonatomic, copy) NSArray<NSString *> *ipv6s;

@property (nonatomic, assign) NSTimeInterval elapsedMs;
@property (nonatomic, assign) NSTimeInterval ttlV4;
@property (nonatomic, assign) NSTimeInterval ttlV6;

- (void)updateWithResult:(HttpdnsResult *)result startTimeMs:(NSTimeInterval)startMs;

@end

