//
//  TestBase.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/14.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "TestBase.h"
#import <mach/mach.h>

NSMutableArray *mockedObjects;
NSDictionary<NSString *, NSString *> *hostNameIpPrefixMap;

@implementation TestBase

+ (void)setUp {
    hostNameIpPrefixMap = @{
        @"v4host1.onlyforhttpdnstest.run.place": @"0.0.1",
        @"v4host2.onlyforhttpdnstest.run.place": @"0.0.2",
        @"v4host3.onlyforhttpdnstest.run.place": @"0.0.3",
        @"v4host4.onlyforhttpdnstest.run.place": @"0.0.4",
        @"v4host5.onlyforhttpdnstest.run.place": @"0.0.5"
    };
}

- (void)setUp {
    [super setUp];

    mockedObjects = [NSMutableArray array];
}

- (void)tearDown {
    for (id object in mockedObjects) {
        [object stopMocking];
    }

    [super tearDown];
}

- (void)log:(NSString *)logStr {
    mach_port_t threadID = mach_thread_self();
    NSString *threadIDString = [NSString stringWithFormat:@"%x", threadID];
    printf("%ld-%s %s\n", (long)[[NSDate date] timeIntervalSince1970], [threadIDString UTF8String], [logStr UTF8String]);
}

- (HttpdnsHostObject *)constructSimpleIpv4HostObject {
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    hostObject.hostName = ipv4OnlyHost;
    hostObject.v4ttl = 60;
    HttpdnsIpObject *ip1 = [[HttpdnsIpObject alloc] init];
    [ip1 setIp:ipv41];
    HttpdnsIpObject *ip2 = [[HttpdnsIpObject alloc] init];
    [ip2 setIp:ipv42];
    hostObject.ips = @[ip1, ip2];
    hostObject.lastIPv4LookupTime = self.currentTimeStamp;
    return hostObject;
}

- (HttpdnsHostObject *)constructSimpleIpv6HostObject {
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    hostObject.hostName = ipv4OnlyHost;
    hostObject.v6ttl = 60;
    HttpdnsIpObject *ip1 = [[HttpdnsIpObject alloc] init];
    [ip1 setIp:@"2001:4860:4860::8888"];
    HttpdnsIpObject *ip2 = [[HttpdnsIpObject alloc] init];
    [ip2 setIp:@"2001:4860:4860::8844"];
    hostObject.ip6s = @[ip1, ip2];
    hostObject.lastIPv6LookupTime = self.currentTimeStamp;
    return hostObject;
}

- (HttpdnsHostObject *)constructSimpleIpv4AndIpv6HostObject {
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    hostObject.hostName = ipv4AndIpv6Host;
    hostObject.v4ttl = 60;
    HttpdnsIpObject *ip1 = [[HttpdnsIpObject alloc] init];
    [ip1 setIp:ipv41];
    HttpdnsIpObject *ip2 = [[HttpdnsIpObject alloc] init];
    [ip2 setIp:ipv42];
    hostObject.ips = @[ip1, ip2];
    hostObject.lastIPv4LookupTime = self.currentTimeStamp;

    hostObject.v6ttl = 60;
    HttpdnsIpObject *ip3 = [[HttpdnsIpObject alloc] init];
    [ip3 setIp:ipv61];
    HttpdnsIpObject *ip4 = [[HttpdnsIpObject alloc] init];
    [ip4 setIp:ipv62];
    hostObject.ip6s = @[ip3, ip4];
    hostObject.lastIPv6LookupTime = self.currentTimeStamp;
    return hostObject;
}

- (void)presetNetworkEnvAsIpv4 {
    AlicloudIPv6Adapter *ipv6Adapter = [AlicloudIPv6Adapter getInstance];
    AlicloudIPv6Adapter *mockIpv6Adapter = OCMPartialMock(ipv6Adapter);
    OCMStub([mockIpv6Adapter currentIpStackType]).andReturn(kAlicloudIPv4only);
    [mockedObjects addObject:mockIpv6Adapter];
}

- (void)presetNetworkEnvAsIpv6 {
    AlicloudIPv6Adapter *ipv6Adapter = [AlicloudIPv6Adapter getInstance];
    AlicloudIPv6Adapter *mockIpv6Adapter = OCMPartialMock(ipv6Adapter);
    OCMStub([mockIpv6Adapter currentIpStackType]).andReturn(kAlicloudIPv6only);
    [mockedObjects addObject:mockIpv6Adapter];
}

- (void)presetNetworkEnvAsIpv4AndIpv6 {
    AlicloudIPv6Adapter *ipv6Adapter = [AlicloudIPv6Adapter getInstance];
    AlicloudIPv6Adapter *mockIpv6Adapter = OCMPartialMock(ipv6Adapter);
    OCMStub([mockIpv6Adapter currentIpStackType]).andReturn(kAlicloudIPdual);
    [mockedObjects addObject:mockIpv6Adapter];
}

- (void)shouldNotHaveCalledRequestWhenResolving:(void (^)(void))resolvingBlock {
    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *scheduler = httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockScheduler = OCMPartialMock(scheduler);
    OCMReject([mockScheduler executeRequest:[OCMArg any] retryCount:0 error:[OCMArg any]]);
    resolvingBlock();
    OCMVerifyAll(mockScheduler);
    [mockedObjects addObject:mockScheduler];
}

- (void)shouldHaveCalledRequestWhenResolving:(void (^)(void))resolvingBlock {
    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
    HttpdnsRequestScheduler *scheduler = httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockScheduler = OCMPartialMock(scheduler);
    OCMExpect([mockScheduler executeRequest:[OCMArg any] retryCount:0 error:[OCMArg any]]).andReturn(nil);
    resolvingBlock();
    OCMVerifyAll(mockScheduler);
    [mockedObjects addObject:mockScheduler];
}

@end
