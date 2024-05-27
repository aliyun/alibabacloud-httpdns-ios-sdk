//
//  PresetCacheAndRetrieveTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/5/26.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>
#import <AlicloudUtils/AlicloudUtils.h>
#import "TestBase.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsRequestScheduler_Internal.h"
#import "HttpdnsService.h"
#import "HttpdnsService_Internal.h"


/**
 * 由于使用OCMock在连续的测试用例中重复Mock对象(即使每次都已经stopMocking)会有内存错乱的问题，
 * 目前还解决不了，所以这个类中的测试case，需要手动单独执行
 */
@interface PresetCacheAndRetrieveTest : TestBase

@property (nonatomic, strong) HttpDnsService *httpdns;

@end


@implementation PresetCacheAndRetrieveTest

+ (void)setUp {
    [super setUp];

    HttpDnsService *httpdns = [[HttpDnsService alloc] initWithAccountID:10000];
    [httpdns setLogEnabled:YES];
    [httpdns setIPv6Enabled:YES];
}

+ (void)tearDown {
    [super tearDown];
}

- (void)setUp {
    [super setUp];

    self.httpdns = [HttpDnsService sharedInstance];
    self.currentTimeStamp = [[NSDate date] timeIntervalSince1970];
}

- (void)tearDown {
    [super tearDown];
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

// 只缓存ipv4单栈的地址，按请求双栈类型存入，此时会标记该域名没有ipv6地址
// 按预期，会判断该域名没有ipv6地址，因此不会返回ipv6地址，也不会发请求
- (void)testMergeNoIpv6ResultAndGetBoth {
    [self presetNetworkEnvAsIpv4AndIpv6];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv4HostObject];
    // 双栈下解析结果仅有ipv4，合并时会标记该host无ipv6
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv4OnlyHost cacheKey:ipv4OnlyHost underQueryIpType:HttpdnsQueryIPTypeBoth];

    [self shouldNotHaveCalledRequestWhenResolving:^{
        HttpdnsResult *result = [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeBoth];
        XCTAssertNotNil(result);
        XCTAssertTrue([result.host isEqualToString:ipv4OnlyHost]);
        XCTAssertTrue([result.ips count] == 2);
        XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
    }];
}

// 缓存ipv4单栈的地址，但是请求ipv4类型存入，此时不会打标记没有ipv6
// 于是，读取时，会尝试发请求获取ipv6地址
- (void)testMergeOnlyIpv4ResultAndGetBoth {
    [self presetNetworkEnvAsIpv4AndIpv6];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv4HostObject];
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv4OnlyHost cacheKey:ipv4OnlyHost underQueryIpType:HttpdnsQueryIPTypeIpv4];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    // 使用同步接口，要切换到异步线程，否则内部会自己切
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self shouldHaveCalledRequestWhenResolving:^{
            HttpdnsResult *result = [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeBoth];
            XCTAssertNil(result);
            dispatch_semaphore_signal(sema);
        }];
    });

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}

// 缓存ipv6单栈的地址，但是请求ipv6类型存入，此时不会打标记没有ipv4
// 于是，读取时，会尝试发请求获取ipv4地址
- (void)testMergeOnlyIpv6ResultAndGetBoth {
    [self presetNetworkEnvAsIpv4AndIpv6];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv6HostObject];
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv6OnlyHost cacheKey:ipv6OnlyHost underQueryIpType:HttpdnsQueryIPTypeIpv6];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    // 使用同步接口，要切换到异步线程，否则内部会自己切
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self shouldHaveCalledRequestWhenResolving:^{
            HttpdnsResult *result = [self.httpdns resolveHostSync:ipv6OnlyHost byIpType:HttpdnsQueryIPTypeBoth];
            XCTAssertNil(result);
            dispatch_semaphore_signal(sema);
        }];
    });

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}

@end
