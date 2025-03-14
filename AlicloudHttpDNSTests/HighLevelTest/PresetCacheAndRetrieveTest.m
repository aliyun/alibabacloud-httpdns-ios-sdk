//
//  PresetCacheAndRetrieveTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2024/5/26.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>
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

@end


@implementation PresetCacheAndRetrieveTest

+ (void)setUp {
    [super setUp];

    HttpDnsService *httpdns = [[HttpDnsService alloc] initWithAccountID:100000];
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

// 网络情况为ipv4下的缓存测试
- (void)testSimplyRetrieveCachedResultUnderIpv4Only {
    [self presetNetworkEnvAsIpv4];
    [self.httpdns cleanAllHostCache];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv4AndIpv6HostObject];
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv4AndIpv6Host cacheKey:ipv4AndIpv6Host underQueryIpType:HttpdnsQueryIPTypeBoth];

    // 请求类型为ipv4，拿到ipv4结果
    HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeIpv4];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);

    // 请求类型为ipv6，拿到ipv6结果
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeIpv6];
    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);

    // both
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeBoth];
    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);

    // 请求类型为auto，只拿到ipv4结果
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeAuto];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
    XCTAssertTrue([result.ipv6s count] == 0);
}

// 网络请求为ipv6下的缓存测试
- (void)testSimplyRetrieveCachedResultUnderIpv6Only {
    [self presetNetworkEnvAsIpv6];
    [self.httpdns cleanAllHostCache];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv4AndIpv6HostObject];
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv4AndIpv6Host cacheKey:ipv4AndIpv6Host underQueryIpType:HttpdnsQueryIPTypeBoth];

    // 请求类型为ipv4，拿到ipv4结果
    HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeIpv4];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);

    // 请求类型为ipv6，拿到ipv6结果
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeIpv6];
    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);

    // both
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeBoth];
    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);

    // 请求类型为auto，注意，我们认为ipv6only只存在理论上，比如实验室环境
    // 因此，ipv4的地址是一定会去解析的，auto的作用在于，如果发现网络还支持ipv6，那就多获取ipv6的结果
    // 因此，这里得到的也是ipv4+ipv6
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeAuto];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);
}

// 网络情况为ipv4和ipv6下的缓存测试
- (void)testSimplyRetrieveCachedResultUnderDualStack {
    [self presetNetworkEnvAsIpv4AndIpv6];
    [self.httpdns cleanAllHostCache];

    // 存入ipv4和ipv6的地址
    HttpdnsHostObject *hostObject = [self constructSimpleIpv4AndIpv6HostObject];
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv4AndIpv6Host cacheKey:ipv4AndIpv6Host underQueryIpType:HttpdnsQueryIPTypeBoth];

    // 只请求ipv4
    HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeIpv4];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);

    // 只请求ipv6
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeIpv6];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);

    // 请求ipv4和ipv6
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeBoth];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);

    // 自动判断类型
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeAuto];

    XCTAssertNotNil(result);
    XCTAssertTrue([result.host isEqualToString:ipv4AndIpv6Host]);
    XCTAssertTrue([result.ips count] == 2);
    XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);
    XCTAssertTrue([result.ipv6s count] == 2);
    XCTAssertTrue([result.ipv6s[0] isEqualToString:ipv61]);
}

// ttl、lastLookupTime，ipv4和ipv6是分开处理的
- (void)testTTLAndLastLookUpTime {
    [self presetNetworkEnvAsIpv4AndIpv6];
    [self.httpdns cleanAllHostCache];

    // 存入ipv4和ipv6的地址
    HttpdnsHostObject *hostObject1 = [self constructSimpleIpv4AndIpv6HostObject];
    hostObject1.ttl = 100;
    hostObject1.v4ttl = 200;
    hostObject1.v6ttl = 300;

    int64_t currentTimestamp = [[NSDate new] timeIntervalSince1970];

    hostObject1.lastLookupTime = currentTimestamp;
    hostObject1.lastIPv4LookupTime = currentTimestamp - 1;
    hostObject1.lastIPv6LookupTime = currentTimestamp - 2;

    // 第一次设置缓存
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject1 host:ipv4AndIpv6Host cacheKey:ipv4AndIpv6Host underQueryIpType:HttpdnsQueryIPTypeBoth];

    // auto在当前环境下即请求ipv4和ipv6
    HttpdnsResult *result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeAuto];
    XCTAssertEqual(result.ttl, hostObject1.v4ttl);
    XCTAssertEqual(result.lastUpdatedTimeInterval, hostObject1.lastIPv4LookupTime);
    XCTAssertEqual(result.v6ttl, hostObject1.v6ttl);
    XCTAssertEqual(result.v6LastUpdatedTimeInterval, hostObject1.lastIPv6LookupTime);

    HttpdnsHostObject *hostObject2 = [self constructSimpleIpv4HostObject];
    hostObject2.hostName = ipv4AndIpv6Host;
    hostObject2.ttl = 500;
    hostObject2.v4ttl = 600;
    hostObject2.lastIPv4LookupTime = currentTimestamp - 10;

    // 单独在缓存更新ipv4地址的相关信息
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject2 host:ipv4AndIpv6Host cacheKey:ipv4AndIpv6Host underQueryIpType:HttpdnsQueryIPTypeIpv4];

    // v4的信息发生变化，v6的信息保持不变
    result = [self.httpdns resolveHostSyncNonBlocking:ipv4AndIpv6Host byIpType:HttpdnsQueryIPTypeAuto];
    XCTAssertEqual(result.ttl, hostObject2.v4ttl);
    XCTAssertEqual(result.lastUpdatedTimeInterval, hostObject2.lastIPv4LookupTime);
    XCTAssertEqual(result.v6ttl, hostObject1.v6ttl);
    XCTAssertEqual(result.v6LastUpdatedTimeInterval, hostObject1.lastIPv6LookupTime);
}

// 只缓存ipv4单栈的地址，按请求双栈类型存入，此时会标记该域名没有ipv6地址
// 按预期，会判断该域名没有ipv6地址，因此不会返回ipv6地址，也不会发请求
- (void)testMergeNoIpv6ResultAndGetBoth {
    [self presetNetworkEnvAsIpv4AndIpv6];

    HttpdnsHostObject *hostObject = [self constructSimpleIpv4HostObject];

    // 双栈下解析结果仅有ipv4，合并时会标记该host无ipv6
    [self.httpdns.requestScheduler mergeLookupResultToManager:hostObject host:ipv4OnlyHost cacheKey:ipv4OnlyHost underQueryIpType:HttpdnsQueryIPTypeBoth];

    [self shouldNotHaveCallNetworkRequestWhenResolving:^{
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            HttpdnsResult *result = [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeBoth];
            XCTAssertNotNil(result);
            XCTAssertTrue([result.host isEqualToString:ipv4OnlyHost]);
            XCTAssertTrue([result.ips count] == 2);
            XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);

            result = [self.httpdns resolveHostSync:ipv4OnlyHost byIpType:HttpdnsQueryIPTypeAuto];
            XCTAssertNotNil(result);
            XCTAssertTrue([result.host isEqualToString:ipv4OnlyHost]);
            XCTAssertTrue([result.ips count] == 2);
            XCTAssertTrue([result.ips[0] isEqualToString:ipv41]);

            dispatch_semaphore_signal(semaphore);
        });

        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
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
