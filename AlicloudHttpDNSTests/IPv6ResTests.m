//
//  IPv6ResTests.m
//  AlicloudHttpDNSTests
//
//  Created by junmo on 2018/11/16.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <AlicloudUtils/AlicloudUtils.h>
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsServiceProvider.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsHostCacheStore.h"

NSString *ipv6Host = @"ipv6.sjtu.edu.cn";
HttpDnsService *httpdns = nil;
HttpdnsRequestScheduler *requestScheduler = nil;

@interface IPv6ResTests : XCTestCase

@end

@implementation IPv6ResTests

+ (void)initialize {
    httpdns = [[HttpDnsService sharedInstance] initWithAccountID:102933];
    requestScheduler = httpdns.requestScheduler;
    [httpdns setLogEnabled:YES];
}

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testCache {
    NSString *fakeHost = @"a.b.com";
    [httpdns getIpByHostAsync:fakeHost];
    sleep(20);
    [httpdns getIpByHostAsync:fakeHost];
}


/**
 测试目的：IPv6解析结果是否正确返回
 测试方法：
 1. 开启v6解析；
 2. 调用v6异步解析接口；
 3. 等待10s；
 4. 再次调用v6异步解析接口，查看是否返回v6地址。
 */
- (void)testGetIPv6Res {
    NSString *ipv6Res = nil;
    [httpdns enableIPv6:YES];
    ipv6Res = [httpdns getIPv6ByHostAsync:ipv6Host];
    XCTAssertNil(ipv6Res);
    sleep(10);
    ipv6Res = [httpdns getIPv6ByHostAsync:ipv6Host];
    XCTAssertNotNil(ipv6Res);
    XCTAssertTrue([[AlicloudIPv6Adapter getInstance] isIPv6Address:ipv6Res]);
}

/**
 测试目的：IPv6解析结果是否持久化缓存正确
 测试方法：
 1. 开启持久化缓存，但缓存不加载到内存；
 2. 开启v6解析；
 3. 清空内存缓存；
 4. 加载持久化缓存；
 5. 校验持久化缓存结果。
 */
- (void)testGetIPv6ResFromCache {
    NSString *ipv6Res = nil;
    // 不会触发持久化缓存加载到内存的动作
    [requestScheduler _setCachedIPEnabled:YES];
    [httpdns enableIPv6:YES];
    ipv6Res = [httpdns getIPv6ByHostAsync:ipv6Host];
    XCTAssertNil(ipv6Res);
    sleep(10);
    [requestScheduler cleanAllHostMemoryCache];
    // 持久化缓存读取为异步执行
    [httpdns setCachedIPEnabled:YES];
    sleep(5);
    ipv6Res = [httpdns getIPv6ByHostAsync:ipv6Host];
    XCTAssertNotNil(ipv6Res);
}

- (void)testTemp {
    
    NSString *testHost = @"ipv6.sjtu.edu.cn";
    NSString *testIPv4 = @"202.120.2.47";
    NSString *testIPv6 = @"2001:da8:8000:1:0:0:0:80";
    NSString *ip4Res = nil;
    NSString *ip6Res = nil;
    NSString *memoryCache = nil;
    NSString *dbCache = nil;
    
    [httpdns enableIPv6:YES];
    HttpdnsHostCacheStore *hostCacheStore = [[HttpdnsHostCacheStore alloc] init];
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:testHost IPs:@[] IP6s:@[ testIPv6 ] TTL:3600];
    [hostCacheStore insertHostRecords:@[hostRecord]];
    sleep(5);
    dbCache = [hostCacheStore showDBCache];
    XCTAssertNotNil(dbCache);
    [httpdns setCachedIPEnabled:YES];
    memoryCache = [requestScheduler showMemoryCache];
    XCTAssertNotNil(memoryCache);
    ip4Res = [httpdns getIpByHostAsync:testHost];
    XCTAssertNil(ip4Res);
    ip6Res = [httpdns getIPv6ByHostAsync:testHost];
    XCTAssertNotNil(ip6Res);
    // 清空内存和持久化缓存
    [self cleanMemoryAndCache:testHost];
    sleep(5);
}

/**
 测试目的：v4和v6解析结果组合，验证各场景解析结果获取
 本测试用例失效，新feature，解析结果如果是从DB加载，下次调用接口一定触发解析
 测试方法：
 
 测试场景           获取v4解析结果                获取v6解析结果
 v4，有效          返回res，不解析               返回res（nil），不解析
 v6，有效          返回res（nil），不解析          返回res，不解析
 v4+v6，有效       返回res，不解析               返回res，不解析
 v4，过期          返回res/nil，解析            返回res（为nil）/nil，解析
 v6，过期          返回res（为nil）/nil，解析      返回res/nil，解析
 v4+v6，过期       返回res/nil，解析            返回res/nil，解析
 */
- (void)testResolveAllScenes {
    NSString *testHost = @"ipv6.sjtu.edu.cn";
    NSString *testIPv4 = @"202.120.2.47";
    NSString *testIPv6 = @"2001:da8:8000:1:0:0:0:80";
    NSString *ip4Res = nil;
    NSString *ip6Res = nil;
    NSString *memoryCache = nil;
    NSString *dbCache = nil;
    
    [httpdns enableIPv6:YES];
    
    // 有效v4
    HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:testHost IPs:@[ testIPv4 ] IP6s: @[] TTL:3600];
    [hostCacheStore insertHostRecords:@[hostRecord]];
    [httpdns setCachedIPEnabled:YES];
    sleep(5);
    ip4Res = [httpdns getIpByHostAsync:testHost];
    XCTAssertNotNil(ip4Res);
    ip6Res = [httpdns getIPv6ByHostAsync:testHost];
    XCTAssertNil(ip6Res);
    // 清空内存和持久化缓存
    [self cleanMemoryAndCache:testHost];
    
    // 有效v6
    hostRecord = [HttpdnsHostRecord hostRecordWithHost:testHost IPs:@[] IP6s:@[ testIPv6 ] TTL:3600];
    [hostCacheStore insertHostRecords:@[hostRecord]];
    sleep(5);
    dbCache = [hostCacheStore showDBCache];
    XCTAssertNotNil(dbCache);
    [httpdns setCachedIPEnabled:YES];
    memoryCache = [requestScheduler showMemoryCache];
    XCTAssertNotNil(memoryCache);
    ip4Res = [httpdns getIpByHostAsync:testHost];
    XCTAssertNil(ip4Res);
    ip6Res = [httpdns getIPv6ByHostAsync:testHost];
    XCTAssertNotNil(ip6Res);
    // 清空内存和持久化缓存
    [self cleanMemoryAndCache:testHost];
    sleep(5);
    
    // 有效v4+v6
    hostRecord = [HttpdnsHostRecord hostRecordWithHost:testHost IPs:@[ testIPv4 ] IP6s:@[ testIPv6 ] TTL:3600];
    [hostCacheStore insertHostRecords:@[hostRecord]];
    sleep(5);
    [httpdns setCachedIPEnabled:YES];
    sleep(5);
    ip4Res = [httpdns getIpByHostAsync:testHost];
    XCTAssertNotNil(ip4Res);
    ip6Res = [httpdns getIPv6ByHostAsync:testHost];
    XCTAssertNotNil(ip6Res);
    // 清空内存和持久化缓存
    [self cleanMemoryAndCache:testHost];
    sleep(5);
    
    // 过期v4
    hostRecord = [HttpdnsHostRecord hostRecordWithHost:testHost IPs:@[ testIPv4 ] IP6s:@[] TTL:0];
    [hostCacheStore insertHostRecords:@[hostRecord]];
    sleep(5);
    [httpdns setCachedIPEnabled:YES];
    sleep(5);
    ip4Res = [httpdns getIpByHostAsync:testHost];
    XCTAssertNil(ip4Res);
    ip6Res = [httpdns getIPv6ByHostAsync:testHost];
    XCTAssertNil(ip6Res);
    // 触发解析动作，等待解析完成后将结果清除
    sleep(10);
    // 清空内存和持久化缓存
    [self cleanMemoryAndCache:testHost];
    sleep(5);
    
    // 过期v6
    hostRecord = [HttpdnsHostRecord hostRecordWithHost:testHost IPs:@[] IP6s:@[ testIPv6 ] TTL:0];
    [hostCacheStore insertHostRecords:@[hostRecord]];
    sleep(5);
    [httpdns setCachedIPEnabled:YES];
    sleep(5);
    ip4Res = [httpdns getIpByHostAsync:testHost];
    XCTAssertNil(ip4Res);
    ip6Res = [httpdns getIPv6ByHostAsync:testHost];
    XCTAssertNil(ip6Res);
    // 触发解析动作，等待解析完成后将结果清除
    sleep(10);
    // 清空内存和持久化缓存
    [self cleanMemoryAndCache:testHost];
    sleep(5);
    
    // 过期v4+v6
    hostRecord = [HttpdnsHostRecord hostRecordWithHost:testHost IPs:@[ testIPv4 ] IP6s:@[ testIPv6 ] TTL:0];
    [hostCacheStore insertHostRecords:@[hostRecord]];
    sleep(5);
    [httpdns setCachedIPEnabled:YES];
    sleep(5);
    // IP过期有效
    [httpdns setExpiredIPEnabled:YES];
    ip4Res = [httpdns getIpByHostAsync:testHost];
    XCTAssertNotNil(ip4Res);
    ip6Res = [httpdns getIPv6ByHostAsync:testHost];
    XCTAssertNotNil(ip6Res);
}

- (void)cleanMemoryAndCache:(NSString *)testHost {
    [requestScheduler cleanAllHostMemoryCache];
    HttpdnsHostCacheStore *hostCacheStore = [HttpdnsHostCacheStore sharedInstance];
    // IPs为nil时，执行删除动作
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:testHost IPs:@[] IP6s:@[] TTL:0];
    [hostCacheStore insertHostRecords:@[hostRecord]];
}

@end
