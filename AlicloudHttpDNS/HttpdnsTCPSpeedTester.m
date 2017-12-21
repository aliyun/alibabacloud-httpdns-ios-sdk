/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#import "HttpdnsTCPSpeedTester.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <fcntl.h>
#import <arpa/inet.h>
#import <netdb.h>
#include <sys/time.h>
#import "AlicloudUtils/AlicloudUtils.h"
#import "HttpdnsServiceProvider_Internal.h"
#import "HttpdnsUtil.h"
#import "HttpDnsHitService.h"

static NSString *const testSpeedKey = @"testSpeed";
static NSString *const ipKey = @"ip";

@implementation HttpdnsTCPSpeedTester

/**
 *  本测速函数，使用linux socket connect 和select函数实现的。 基于以下原理
 *  1. 即使套接口是非阻塞的。如果连接的服务器在同一台主机上，那么在调用connect 建立连接时，连接通常会立即建立成功，我们必须处理这种情况。
 *  2. 源自Berkeley的实现(和Posix.1g)有两条与select 和非阻塞IO相关的规则：
 *     A. 当连接建立成功时，套接口描述符变成可写；
 *     B. 当连接出错时，套接口描述符变成既可读又可写。
 *  @param ip 用于测速对Ip，应该是IPv4格式。
 *
 *  @return 测速结果，单位时毫秒，HTTPDNS_SOCKET_CONNECT_TIMEOUT_RTT 代表超时。
 */
- (int)testSpeedOf:(NSString *)ip {
    return [self testSpeedOf:ip port:80];
}
/*!
 * 如果用户对域名提供多个端口，取任意一个端口。
 
 假设：同一个域名，不同端口到达速度一致。
 
 
 
 让优选逻辑，尽量少de
 15s 100s
 
 - IP池在2个到5个范围内，才进行测速逻辑。
 - 只在ttl未过期内测试。
 - ~~只取内存缓存，与持久化缓存逻辑不产生交集。持久化优先级更高。~~ 无法区分持久化，持久化缓存也可能参与排序。
 - 测速逻辑公开，作为最佳实践。
 - 只在 IPv4 逻辑下测试，IPv6 环境不测。
 - 测速逻辑不能增加用户计费请求次数。
 - 预加载也参与IP优选，网络请求成功就异步排序。
 -
 */
- (NSArray<NSString *> *)ipRankingWithIPs:(NSArray<NSString *> *)IPs host:(NSString *)host {
    NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@, \n %@", @(__PRETTY_FUNCTION__), @(__LINE__), IPs, host);
    if ([[self class] isIPv6OnlyNetwork]) {
        return nil;
    }
    if (![HttpdnsUtil isValidArray:IPs]) {
        return nil;
    }
    if (IPs.count < 2 || IPs.count > 9) {
        return nil;
    }
    if (![HttpdnsUtil isValidString:host]) {
        return nil;
    }
    
    //TODO:  如何 host不在IP排序列表中。
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSDictionary<NSString *, NSString *> *dataSource = sharedService.IPRankingDataSource;
    NSArray *allHost = [dataSource allKeys];
    if (!allHost || allHost.count == 0) {
        return nil;
    }
    if (![allHost containsObject:host]) {
        return nil;
    }
    
    //TODO:  添加port查询
    int16_t port = 80;//
    @try {
        id port_ = dataSource[host];
        port = [port_ integerValue];
    } @catch (NSException *exception) {}
    //TODO:  port 正则匹配
    
    NSMutableArray<NSDictionary *> *IPSpeeds = [NSMutableArray arrayWithCapacity:IPs.count];
    for (NSString *ip in IPs) {
        int testSpeed =  [self testSpeedOf:ip port:port];
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@, %@ms", @(__PRETTY_FUNCTION__), @(__LINE__), ip, @(testSpeed));
        NSMutableDictionary *IPSpeed = [NSMutableDictionary dictionaryWithCapacity:2];
        [IPSpeed setObject:@(testSpeed) forKey:testSpeedKey];
        [IPSpeed setObject:ip forKey:ipKey];
        [IPSpeeds addObject:IPSpeed];
    }
    
    NSArray *sortedIPSpeedsArray = [IPSpeeds sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        long data1 = [[obj1 valueForKey:testSpeedKey] integerValue];
        long data2 = [[obj2 valueForKey:testSpeedKey] integerValue];
        return (data1 > data2) ? NSOrderedDescending : NSOrderedAscending;
    }];
    
    NSMutableArray<NSString *> *sortedArrayIPs = [NSMutableArray arrayWithCapacity:IPs.count];
    for (NSDictionary *dict in sortedIPSpeedsArray) {
       NSString *ip = [dict objectForKey:ipKey];
        [sortedArrayIPs addObject:ip];
    }
    //保证数量一致，
    if (sortedArrayIPs.count == IPs.count) {
        [self asyncHitWithDefaultIps:IPs sortedIPSpeedsArray:sortedIPSpeedsArray host:host];
        NSLog(@"🔴类名与方法名：%@（在第%@行），描述：%@, %@", @(__PRETTY_FUNCTION__), @(__LINE__),IPs,  sortedIPSpeedsArray);
        return [sortedArrayIPs copy];
    }
    return nil;
}

/*!
 * defaultIp    默认返回的IP，原有IP列表中的第一位
 selectedIp    优选后返回的IP
 defaultIpCost    用默认IP进行建连的时间开销，建连超时为无穷大
 selectedIpCost    优选IP进行建连的时间开销
 */
//TODO:
- (void)asyncHitWithDefaultIps:(NSArray *)defaultIps sortedIPSpeedsArray:(NSArray *)sortedIPSpeedsArray host:(NSString *)host {
    NSString *defaultIp;
    NSNumber *defaultIpCost;
    NSNumber *selectedIpCost;
    //TODO:  add try catch
//    @try {
        defaultIp = defaultIps[0];
//    } @catch (NSException *exception) {}
    
    NSString *selectedIp;
    
    //TODO:  add try catch
//    @try {
        NSDictionary *sortedIPSpeed = sortedIPSpeedsArray[0];
        selectedIp = sortedIPSpeed[ipKey];
        selectedIpCost = sortedIPSpeed[testSpeedKey];
//    } @catch (NSException *exception) {}
    
//    //构造元素需要使用两个空格来进行缩进，右括号]或者}写在新的一行，并且与调用语法糖那行代码的第一个非空字符对齐：
//    NSArray *array =
//    @[
//      @{
//          ipKey : @"a",
//          testSpeedKey : @(1)
//          },
//      @{
//          ipKey : @"b",
//          testSpeedKey : @(2)
//          },
//      @{
//          ipKey : @"c",
//          testSpeedKey : @(3)
//          }
//      ];
   NSPredicate *defaultIpCostPredicate = [NSPredicate predicateWithFormat:@"%@ = '%@'", ipKey, defaultIp];
   NSArray *defaultIpCostArray = [sortedIPSpeedsArray filteredArrayUsingPredicate:defaultIpCostPredicate];
    
    if (defaultIpCostArray.count > 0) {
        NSDictionary *defaultIpCostDict = defaultIpCostArray[0];
        defaultIpCost = defaultIpCostDict[testSpeedKey];
    }
    [self asyncHitWithHost:host
                 defaultIp:defaultIp
                     selectedIp:selectedIp
                  defaultIpCost:defaultIpCost
                 selectedIpCost:selectedIpCost];
}

- (void)asyncHitWithHost:(NSString *)host
defaultIp:(NSString *)defaultIp
                   selectedIp:(NSString *)selectedIp
                defaultIpCost:(NSNumber *)defaultIpCost
               selectedIpCost:(NSNumber *)selectedIpCost {
//TODO: 上传日志
    [HttpDnsHitService bizIPSelectionWithHost:host
                                    defaultIp:defaultIp
                                   selectedIp:selectedIp
                                defaultIpCost:defaultIpCost
                               selectedIpCost:selectedIpCost];
}

+ (BOOL)isIPv6OnlyNetwork {
    return [[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork];
}

- (int)testSpeedOf:(NSString *)ip port:(int16_t)port {
    NSString *oldIp = ip;
    //TODO:  IPv6 不考虑
    //    if (![HttpdnsTools isIpV4Address:ip]) {
    //        //TODO:  从 HTTPDNS 中获取到IP数组
    //        //TODO:  这里会有
    //        //TODO:  但是不能触发计费请求
    //        ip = [self getHostByName:ip];
    //        if (!ip) {
    //            NSLog(@"ERROR:%s:%d, params(%@) is invalid.",__FUNCTION__,__LINE__, oldIp);
    //            return 0;
    //        }
    //    }
    //request time out
    float rtt = 0.0;
    //sock：将要被设置或者获取选项的套接字。
    int s = 0;
    struct sockaddr_in saddr;
    saddr.sin_family = AF_INET;
    // MARK: - 设置端口，这里需要根据需要自定义，默认是80端口。
    saddr.sin_port = htons(port);
    saddr.sin_addr.s_addr = inet_addr([ip UTF8String]);
    //saddr.sin_addr.s_addr = inet_addr("1.1.1.123");
    if( (s=socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        NSLog(@"ERROR:%s:%d, create socket failed.",__FUNCTION__,__LINE__);
        return 0;
    }
    NSDate *startTime = [NSDate date];
    NSDate *endTime;
    //为了设置connect超时 把socket设置称为非阻塞
    int flags = fcntl(s, F_GETFL,0);
    fcntl(s,F_SETFL, flags | O_NONBLOCK);
    //对于阻塞式套接字，调用connect函数将激发TCP的三次握手过程，而且仅在连接建立成功或者出错时才返回；
    //对于非阻塞式套接字，如果调用connect函数会之间返回-1（表示出错），且错误为EINPROGRESS，表示连接建立，建立启动但是尚未完成；
    //如果返回0，则表示连接已经建立，这通常是在服务器和客户在同一台主机上时发生。
    int i = connect(s,(struct sockaddr*)&saddr, sizeof(saddr));
    if(i == 0) {
        //建立连接成功，返回rtt时间。 因为connect是非阻塞，所以这个时间就是一个函数执行的时间，毫秒级，没必要再测速了。
        close(s);
        return 1;
    }
    struct timeval tv;
    int valopt;
    socklen_t lon;
    tv.tv_sec = HTTPDNS_SOCKET_CONNECT_TIMEOUT;
    tv.tv_usec = 0;
    
    //TODO:  myset ?
    fd_set myset;
    FD_ZERO(&myset);
    FD_SET(s, &myset);
    
    // MARK: - 使用select函数，对套接字的IO操作设置超时。
    /**
     select函数
     select是一种IO多路复用机制，它允许进程指示内核等待多个事件的任何一个发生，并且在有一个或者多个事件发生或者经历一段指定的时间后才唤醒它。
     connect本身并不具有设置超时功能，如果想对套接字的IO操作设置超时，可使用select函数。
     **/
    int maxfdp = s+1;
    int j = select(maxfdp, NULL, &myset, NULL, &tv);
    
    if (j == 0) {
        NSLog(@"INFO:%s:%d, test rtt of (%@) timeout.",__FUNCTION__,__LINE__, oldIp);
        rtt = HTTPDNS_SOCKET_CONNECT_TIMEOUT_RTT;
        close(s);
        return rtt;
    }
    
    if (j < 0) {
        NSLog(@"ERROR:%s:%d, select function error.",__FUNCTION__,__LINE__);
        rtt = 0;
        close(s);
        return rtt;
    }
    
    /**
     对于select和非阻塞connect，注意两点：
     [1] 当连接成功建立时，描述符变成可写； [2] 当连接建立遇到错误时，描述符变为即可读，也可写，遇到这种情况，可调用getsockopt函数。
     **/
    //    if (j > 0) {
    lon = sizeof(int);
    //valopt 表示错误信息。
    // MARK: - 测试核心逻辑，连接后，获取错误信息，如果没有错误信息就是访问成功
    /*!
     * //getsockopt函数可获取影响套接字的选项，比如SOCKET的出错信息
     * (get socket option)
     */
    getsockopt(s, SOL_SOCKET, SO_ERROR, (void*)(&valopt), &lon);
    //如果有错误信息：
    if (valopt) {
        NSLog(@"ERROR:%s:%d, select function error.",__FUNCTION__,__LINE__);
        rtt = 0;
    } else {
        endTime = [NSDate date];
        rtt = [endTime timeIntervalSinceDate:startTime] * 1000;
    }
    //    }
    close(s);
    return rtt;
}

@end
