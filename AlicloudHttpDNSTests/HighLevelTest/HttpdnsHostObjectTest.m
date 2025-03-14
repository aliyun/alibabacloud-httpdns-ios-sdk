//
//  HttpdnsHostObjectTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2025/3/14.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../Testbase/TestBase.h"
#import "HttpdnsHostObject.h"
#import "HttpdnsIpObject.h"
#import <OCMock/OCMock.h>

@interface HttpdnsHostObjectTest : TestBase

@end

@implementation HttpdnsHostObjectTest

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - 基本属性测试

- (void)testHostObjectProperties {
    // 创建一个HttpdnsHostObject实例
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];

    // 设置基本属性
    hostObject.host = @"example.com";
    hostObject.ttl = 60;
    hostObject.queryTimes = 1;
    hostObject.clientIP = @"192.168.1.1";

    // 验证属性值
    XCTAssertEqualObjects(hostObject.host, @"example.com", @"host属性应该被正确设置");
    XCTAssertEqual(hostObject.ttl, 60, @"ttl属性应该被正确设置");
    XCTAssertEqual(hostObject.queryTimes, 1, @"queryTimes属性应该被正确设置");
    XCTAssertEqualObjects(hostObject.clientIP, @"192.168.1.1", @"clientIP属性应该被正确设置");
}

#pragma mark - IP对象测试

- (void)testIpObjectProperties {
    // 创建一个HttpdnsIpObject实例
    HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];

    // 设置基本属性
    ipObject.ip = @"1.2.3.4";
    ipObject.ttl = 300;
    ipObject.priority = 10;
    ipObject.detectRT = 50;  // 测试新添加的detectRT属性

    // 验证属性值
    XCTAssertEqualObjects(ipObject.ip, @"1.2.3.4", @"ip属性应该被正确设置");
    XCTAssertEqual(ipObject.ttl, 300, @"ttl属性应该被正确设置");
    XCTAssertEqual(ipObject.priority, 10, @"priority属性应该被正确设置");
    XCTAssertEqual(ipObject.detectRT, 50, @"detectRT属性应该被正确设置");
}

- (void)testIpObjectDetectRTMethods {
    // 创建一个HttpdnsIpObject实例
    HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];

    // 测试默认值
    XCTAssertEqual(ipObject.detectRT, -1, @"detectRT的默认值应该是-1");

    // 测试设置检测时间
    [ipObject setDetectRT:100];
    XCTAssertEqual(ipObject.detectRT, 100, @"detectRT应该被正确设置为100");

    // 测试设置为负值
    [ipObject setDetectRT:-5];
    XCTAssertEqual(ipObject.detectRT, -1, @"设置负值时detectRT应该被设置为-1");

    // 测试设置为0
    [ipObject setDetectRT:0];
    XCTAssertEqual(ipObject.detectRT, 0, @"detectRT应该被正确设置为0");
}

#pragma mark - 主机对象IP管理测试

- (void)testHostObjectIpManagement {
    // 创建一个HttpdnsHostObject实例
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    hostObject.host = @"example.com";

    // 创建IP对象
    HttpdnsIpObject *ipv4Object = [[HttpdnsIpObject alloc] init];
    ipv4Object.ip = @"1.2.3.4";
    ipv4Object.ttl = 300;
    ipv4Object.detectRT = 50;

    HttpdnsIpObject *ipv6Object = [[HttpdnsIpObject alloc] init];
    ipv6Object.ip = @"2001:db8::1";
    ipv6Object.ttl = 600;
    ipv6Object.detectRT = 80;

    // 添加IP对象到主机对象
    [hostObject addIpv4:ipv4Object];
    [hostObject addIpv6:ipv6Object];

    // 验证IP对象是否被正确添加
    XCTAssertEqual(hostObject.ipv4List.count, 1, @"应该有1个IPv4对象");
    XCTAssertEqual(hostObject.ipv6List.count, 1, @"应该有1个IPv6对象");

    // 验证IP对象的属性
    HttpdnsIpObject *retrievedIpv4 = hostObject.ipv4List.firstObject;
    XCTAssertEqualObjects(retrievedIpv4.ip, @"1.2.3.4", @"IPv4地址应该正确");
    XCTAssertEqual(retrievedIpv4.detectRT, 50, @"IPv4的detectRT应该正确");

    HttpdnsIpObject *retrievedIpv6 = hostObject.ipv6List.firstObject;
    XCTAssertEqualObjects(retrievedIpv6.ip, @"2001:db8::1", @"IPv6地址应该正确");
    XCTAssertEqual(retrievedIpv6.detectRT, 80, @"IPv6的detectRT应该正确");
}

#pragma mark - IP排序测试

- (void)testIpSortingByDetectRT {
    // 创建一个HttpdnsHostObject实例
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    hostObject.host = @"example.com";

    // 创建多个IP对象，具有不同的检测时间
    HttpdnsIpObject *ip1 = [[HttpdnsIpObject alloc] init];
    ip1.ip = @"1.1.1.1";
    ip1.detectRT = 100;

    HttpdnsIpObject *ip2 = [[HttpdnsIpObject alloc] init];
    ip2.ip = @"2.2.2.2";
    ip2.detectRT = 50;

    HttpdnsIpObject *ip3 = [[HttpdnsIpObject alloc] init];
    ip3.ip = @"3.3.3.3";
    ip3.detectRT = 200;

    HttpdnsIpObject *ip4 = [[HttpdnsIpObject alloc] init];
    ip4.ip = @"4.4.4.4";
    ip4.detectRT = -1;  // 未检测

    // 添加IP对象到主机对象（顺序不重要）
    [hostObject addIpv4:ip1];
    [hostObject addIpv4:ip2];
    [hostObject addIpv4:ip3];
    [hostObject addIpv4:ip4];

    // 获取排序后的IP列表
    NSArray<HttpdnsIpObject *> *sortedIps = [hostObject sortedIpv4List];

    // 验证排序结果
    // 预期顺序：ip2(50ms) -> ip1(100ms) -> ip3(200ms) -> ip4(-1ms)
    XCTAssertEqual(sortedIps.count, 4, @"应该有4个IP对象");
    XCTAssertEqualObjects(sortedIps[0].ip, @"2.2.2.2", @"检测时间最短的IP应该排在第一位");
    XCTAssertEqualObjects(sortedIps[1].ip, @"1.1.1.1", @"检测时间第二短的IP应该排在第二位");
    XCTAssertEqualObjects(sortedIps[2].ip, @"3.3.3.3", @"检测时间第三短的IP应该排在第三位");
    XCTAssertEqualObjects(sortedIps[3].ip, @"4.4.4.4", @"未检测的IP应该排在最后");
}

@end