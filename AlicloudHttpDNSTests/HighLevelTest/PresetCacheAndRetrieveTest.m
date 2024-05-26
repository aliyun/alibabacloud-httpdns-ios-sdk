//
//  PresetCacheAndRetrieveTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/5/26.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TestBase.h"
#import <AlicloudUtils/AlicloudUtils.h>
#import <OCMock/OCMock.h>
#import "HttpdnsHostObject.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsService.h"
#import "HttpdnsService_Internal.h"


@interface PresetCacheAndRetrieveTest : TestBase

@property (nonatomic, assign) NSTimeInterval currentTimeStamp;

@property (nonatomic, strong) HttpDnsService *httpdns;

@end

static NSString *ipv4OnlyHost = @"ipv4.only.com";
static NSString *ipv6OnlyHost = @"ipv6.only.com";
static NSString *ipv4AndIpv6Host = @"ipv4.and.ipv6.com";

static NSString *ipv41 = @"1.1.1.1";
static NSString *ipv42 = @"2.2.2.2";
static NSString *ipv61 = @"2001:4860:4860::8888";
static NSString *ipv62 = @"2001:4860:4860::8844";

static NSMutableArray *mockedObjects;

@implementation PresetCacheAndRetrieveTest

- (void)setUp {
    [super setUp];

    mockedObjects = [NSMutableArray array];

    self.httpdns = [[HttpDnsService alloc] initWithAccountID:10000];
    [self.httpdns setLogEnabled:YES];
    [self.httpdns setIPv6Enabled:YES];

    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (void)tearDown {
    for (id object in mockedObjects) {
        [object stopMocking];
    }

    [super tearDown];
}

- (HttpdnsHostObject *)constructSimpleIpv4HostObject {
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    hostObject.hostName = ipv4OnlyHost;
    hostObject.ttl = 60;
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
    hostObject.ttl = 60;
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
    hostObject.ttl = 60;
    HttpdnsIpObject *ip1 = [[HttpdnsIpObject alloc] init];
    [ip1 setIp:ipv41];
    HttpdnsIpObject *ip2 = [[HttpdnsIpObject alloc] init];
    [ip2 setIp:ipv42];
    hostObject.ips = @[ip1, ip2];
    hostObject.lastIPv4LookupTime = self.currentTimeStamp;

    HttpdnsIpObject *ip3 = [[HttpdnsIpObject alloc] init];
    [ip3 setIp:ipv61];
    HttpdnsIpObject *ip4 = [[HttpdnsIpObject alloc] init];
    [ip4 setIp:ipv62];
    hostObject.ip6s = @[ip3, ip4];
    hostObject.lastIPv6LookupTime = self.currentTimeStamp;
    return hostObject;
}

- (void)presetNetworkEnvAsIpv4 {
    id mockAlicloudIPv6Adapter = OCMClassMock([AlicloudIPv6Adapter class]);
    OCMStub([mockAlicloudIPv6Adapter getInstance]).andReturn(mockAlicloudIPv6Adapter);
    OCMStub([mockAlicloudIPv6Adapter currentIpStackType]).andReturn(kAlicloudIPv4only);
    [mockedObjects addObject:mockAlicloudIPv6Adapter];
}

- (void)presetNetworkEnvAsIpv6 {
    id mockAlicloudIPv6Adapter = OCMClassMock([AlicloudIPv6Adapter class]);
    OCMStub([mockAlicloudIPv6Adapter getInstance]).andReturn(mockAlicloudIPv6Adapter);
    OCMStub([mockAlicloudIPv6Adapter currentIpStackType]).andReturn(kAlicloudIPv6only);
    [mockedObjects addObject:mockAlicloudIPv6Adapter];
}

- (void)presetNetworkEnvAsIpv4AndIpv6 {
    id mockAlicloudIPv6Adapter = OCMClassMock([AlicloudIPv6Adapter class]);
    OCMStub([mockAlicloudIPv6Adapter getInstance]).andReturn(mockAlicloudIPv6Adapter);
    OCMStub([mockAlicloudIPv6Adapter currentIpStackType]).andReturn(kAlicloudIPdual);
    [mockedObjects addObject:mockAlicloudIPv6Adapter];
}

- (void)shouldNotHaveCalledRequestWhenResolving:(void (^)(void))resolvingBlock {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockScheduler = OCMPartialMock(scheduler);
    OCMReject([mockScheduler executeRequest:[OCMArg any] retryCount:0 activatedServerIPIndex:0 error:[OCMArg any]]).andReturn(nil);
    resolvingBlock();
    OCMVerifyAll(mockScheduler);
    [mockedObjects addObject:mockScheduler];
}

- (void)shouldHaveCalledRequestWhenResolving:(void (^)(void))resolvingBlock {
    HttpdnsRequestScheduler *scheduler = self.httpdns.requestScheduler;
    HttpdnsRequestScheduler *mockScheduler = OCMPartialMock(scheduler);
    OCMExpect([mockScheduler executeRequest:[OCMArg any] retryCount:0 activatedServerIPIndex:0 error:[OCMArg any]]).andReturn(nil);
    resolvingBlock();
    OCMVerifyAll(mockScheduler);
    [mockedObjects addObject:mockScheduler];
}

// 缓存ipv4的地址，网络情况为ipv4，正常返回ipv4的地址
- (void)testSimplyRetrieveIpv4CachedResult {
    [self presetNetworkEnvAsIpv4];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv4HostObject];
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv4OnlyHost cacheKey:ipv4OnlyHost underQueryIpType:HttpdnsQueryIPTypeIpv4];

    HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeIpv4];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4OnlyHost]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
}

// 缓存ipv6的地址，网络情况为ipv6，正常返回ipv6的地址
- (void)testSimplyRetrieveIpv6CachedResult {
    [self presetNetworkEnvAsIpv6];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv6HostObject];
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv6OnlyHost cacheKey:ipv6OnlyHost underQueryIpType:HttpdnsQueryIPTypeIpv6];

    HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:ipv6OnlyHost byIpType:HttpdnsQueryIPTypeIpv6];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv6OnlyHost]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);
}

// 缓存ipv4和ipv6的地址，网络情况为ipv4和ipv6，正常返回ipv4和ipv6的地址
- (void)testSimplyRetrieveIpv4AndIpv6CachedResult {
    [self presetNetworkEnvAsIpv4AndIpv6];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv4AndIpv6HostObject];
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv4AndIpv6Host cacheKey:ipv4AndIpv6Host underQueryIpType:HttpdnsQueryIPTypeBoth];

    HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeIpv4];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);

    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeIpv6];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);

    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeBoth];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);
}

@end
