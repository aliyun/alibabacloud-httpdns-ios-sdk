//
//  HttpdnsQATest.m
//  ALBBHttpdnsSDK
//
//  Created by zhouzhuo on 6/9/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TestIncludeAllHeader.h"
#import "TestResouces.h"

@interface HttpdnsQATest : XCTestCase
@end

static NSString * aliyunHost = @"www.aliyun.com";
static id<ALBBHttpdnsServiceProtocol> httpdns;
static HttpdnsRequestScheduler * scheduler;
static NSMutableDictionary * hostManager;

NSString * test_host1 = @"www.xxyycc.com";
NSString * test_ip1 = @"121.41.73.79";
NSString * test_host2 = @"dns.com";
NSString * test_ip2 = @"117.28.255.25";

@implementation HttpdnsQATest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    [HttpdnsLocalCache cleanLocalCache];
    httpdns = [HttpDnsServiceProvider getService];
    [HttpdnsLog enbaleLog];
    HttpDnsServiceProvider * instance = (HttpDnsServiceProvider *)httpdns;
    scheduler = [instance requestScheduler];
    hostManager = [scheduler hostManagerDict];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

/**
 * 测试目的：测试Cache 自动更新功能。
 * 测试方法：1.先设置一个马上就会过期的Cache；2.过期获取一个Cache应是过期IP; 3.再获取两次判断是否更新;
 */
- (void)testTTL {
    HttpdnsHostObject * hostObject = [TestResouces buildAnHostObjectWithHostName:test_host1
                                                                         withTTL:1
                                                                          withIp:@"1.1.1.1"
                                                                  withLookupTime:[HttpdnsUtil currentEpochTimeInSecond]
                                                                       withState:VALID];
    [hostManager setObject:hostObject forKey:test_host1];
    sleep(2);
    XCTAssertEqual([httpdns getIpByHostAsync:test_host1], @"1.1.1.1", "Should return old ip");
    NSLog(@"return ip: %@", [httpdns getIpByHost:test_host1]);
    // XCTAssertEqual([httpdns getIpByHost:test_host1], test_ip1, "Should update ip");
    XCTAssertEqualObjects([httpdns getIpByHost:test_host1], test_ip1, "Should update ip");
    HttpdnsLogDebug(@"[testTTL] - %@", [httpdns getIpByHost:test_host1]);
    XCTAssertEqualObjects([httpdns getIpByHostAsync:test_host1], test_ip1, "Should update ip");
}

/**
 * 测试目的：高并发场景能正常解析
 * 测试方法：
 */
- (void)testHttpdnsLargeConcurent {
}

/**
 * 测试目的：开启若干个线程同时设置预解析域名，最后结果正常
 * 测试方法：1.同时异步10个线程预解析域名；2.过一段时间(3秒)以后获取看是否正常。
 */
- (void)testConcurrentlySetPreResolve {
    for (int i = 0; i < 10; i++) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray * hosts = [[NSArray alloc] initWithObjects:test_host1, test_host2, nil];
            [httpdns setPreResolveHosts:hosts];
        });
    }
    sleep(3);
    NSString * resolvedIp1 = [httpdns getIpByHost:test_host1];
    NSString * resolvedIp2 = [httpdns getIpByHostAsync:test_host2];
    XCTAssertEqualObjects(resolvedIp1, test_ip1, @"Should be equal!");
    XCTAssertEqualObjects(resolvedIp2, test_ip2, @"Should be equal!");
}

/**
 * 测试目的：失败一定次数后降级到使用域名请求httpdns server
 * 测试方法：1.频繁发出失败消息使得降级；2.检测获取IP是否正常
 */
- (void)testServerIpDegradeToHost {
    NSString * resolvedIp1 = [httpdns getIpByHost:test_host1];
    XCTAssertEqualObjects(resolvedIp1, test_ip1, @"Should be equal!");
    for (int i = 0; i < 10; i++) {
        [HttpdnsRequest notifyRequestFailed];
    }
    NSString * resolvedIp2 = [httpdns getIpByHost: test_host2];
    XCTAssertEqualObjects(resolvedIp2, test_ip2, @"Should be equal!");
}

/**
 * 测试目的：测试本地缓存读写
 * 测试方法：1.写入一个host到本地缓存；2.从本地缓存读取host缓存；3.验证缓存中的数据；
 */
- (void)testLocalCacheReadWrite {
    HttpdnsHostObject * hostObject = [TestResouces buildAnHostObjectWithHostName:@"test.domain.com"
                                                                         withTTL:30
                                                                          withIp:@"1.1.1.1"
                                                                  withLookupTime:[HttpdnsUtil currentEpochTimeInSecond]
                                                                       withState:VALID];
    [hostManager setObject:hostObject forKey:@"test.domain.com"];
    [HttpdnsLocalCache writeToLocalCache:hostManager];
    NSDictionary * cacheHosts = [HttpdnsLocalCache readFromLocalCache];
    [scheduler readCacheHosts:cacheHosts];
    NSString * resolvedIp = [httpdns getIpByHostAsync:@"test.domain.com"];
    XCTAssertEqualObjects(resolvedIp, @"1.1.1.1", "Not equal");
    resolvedIp = [httpdns getIpByHost:@"test.domain.com"];
    XCTAssertEqualObjects(resolvedIp, @"1.1.1.1", "Not equal");
}

- (void)testIsLogicHost {
}

/**
 * 测试目的：查询一个不存在的host，应该返回nil
 * 测试方法：给出一个不存在的host进行查询，检查结果是否为nil
 */
- (void)testNotExistHost {
    NSString * notExistHost = @"notexitsthostindnssystem.com";
    NSString * resolvedIp = [httpdns getIpByHostAsync:notExistHost];
    XCTAssertNil(resolvedIp, @"Should return nil when host not exist!");
    resolvedIp = [httpdns getIpByHost:notExistHost];
    XCTAssertNil(resolvedIp, @"Should return nil when host not exist!");
}

/**
 * 测试目的：查询一个ip格式的host，应该返回ip本身
 * 测试方法：给出一个ip进行查询，检查获取的结果是否为它本身
 */
- (void)testIsLogicIp {
    NSString * testIp = @"1.1.1.1";
    NSString * resolvedIp = [httpdns getIpByHost:testIp];
    XCTAssertEqualObjects(testIp, resolvedIp, @"Not equal");
    resolvedIp = [httpdns getIpByHostAsync:testIp];
    XCTAssertEqualObjects(testIp, resolvedIp, @"Not equal");
}

/**
 * 测试目的：测试host合法判断功能
 * 测试方法：给出用例，判断是否能正确测试出是否为host
 */
-(void)testHostLegalJudge{
    NSString *host1 = @"nihao";
    NSString *host2 = @"baidu.com";
    NSString *host3 = @"https://www.baidu.com/";
    NSString *host4 = @"zhihu.com";
    NSString *host5 = @"123123/32,daf";
    XCTAssertEqual([HttpdnsUtil checkIfIsAnHost:host1], YES, "Should be YES");
    XCTAssertEqual([HttpdnsUtil checkIfIsAnHost:host2], YES, "Should be YES");
    XCTAssertEqual([HttpdnsUtil checkIfIsAnHost:host3], NO, "Should be NO");
    XCTAssertEqual([HttpdnsUtil checkIfIsAnHost:host4], YES, "Should be YES");
    XCTAssertEqual([HttpdnsUtil checkIfIsAnHost:host5], NO, "Should be NO");
}
@end
