//
//  ViewController.m
//  AlicloudHttpDNSTestDemo
//
//  Created by junmo on 2018/8/3.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import "ViewController.h"
#import "HttpdnsServiceProvider.h"
#import "HttpdnsUtil.h"
#import "MyLoggerHandler.h"
#import "HttpdnsScheduleCenter.h"
#import "TestIPv6ViewController.h"

#import "HttpdnsServiceProvider_Internal.h"

#import <AlicloudUtils/AlicloudIPv6Adapter.h>

NSArray *ipv4HostArray = nil;
NSArray *ipv6HostArray = nil;

@interface ViewController ()

@property (nonatomic, strong) HttpDnsService *service;
@property (nonatomic, strong) HttpdnsScheduleCenter *sc;
@property (nonatomic, strong) MyLoggerHandler *logHandler;

@end

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    
    ipv4HostArray = @[
                      @"m.u17.com",
                      @"live-dev-cstest.fzzqxf.com",
                      @"ios-dev-cstest.fzzqxf.com",
                      @"gateway.vtechl1.com",
                      @"www.163.com",
                      @"www.douban.com",
                      @"api.thekillboxgame.com",
                      @"data.zhibo8.cc",
                      @"www.12306.cn",
                      @"t.yunjiweidian.com",
                      @"dca.qiumibao.com",
                      @"home.cochat.lenovo.com",
                      @"ra.namibox.com",
                      @"namibox.com",
                      @"feature.yoho.cn",
                      @"image2.benlailife.com",
                      @"dou.bz",
                      @"book.douban.com",
                      @"cdn.yoho.cn",
                      @"gw.alicdn.com",
                      @"www.taobao.com",
                      @"www.apple.com",
                      @"guang.m.yohobuy.com",
                      @"www.tmall.com",
                      @"www.aliyun.com"
                      ];
    ipv6HostArray = @[
                      @"tv6.ustc.edu.cn",
                      @"ipv6.sjtu.edu.cn"
                      ];

    NSString *sessionId = [[HttpDnsService sharedInstance] getSessionId];
    NSLog(@"Print sessionId: %@", sessionId);

    // ams_test账号139450
    _service = [[HttpDnsService alloc] initWithAccountID:139450];
    [_service setLogEnabled:YES];
    [_service setCachedIPEnabled:YES];
    [_service setExpiredIPEnabled:NO];
    [_service setHTTPSRequestEnabled:YES];
    [_service enableIPv6:YES];

    [_service setIPRankingDatasource:@{@"dns.xuyecan1919.tech": @443}];
}



- (IBAction)onHost1:(id)sender {
    AlicloudIPStackType stackType = [_service currentIpStack];
    NSLog(@"onHost1, stackType: %d", stackType);

    // for (NSString *ipv4Host in ipv4HostArray) {
    //     [_service asyncGetHostByName:ipv4Host completionHandler:^(NSDictionary<NSString *,NSString *> *result) {
    //         NSLog(@"host: %@, result: %@", ipv4Host, result);
    //     }];
    // }
    // for (NSString *ipv6Host in ipv6HostArray) {
    //     [_service asyncGetHostByName:ipv6Host completionHandler:^(NSDictionary<NSString *,NSString *> *result) {
    //         NSLog(@"host: %@, result: %@", ipv6Host, result);
    //     }];
    // }
}

- (IBAction)onHost2:(id)sender {
    // [_service asyncGetHostByName:@"dns.xuyecan1919.tech" completionHandler:^(NSDictionary<NSString *,NSString *> *result) {
    //     NSLog(@"host2: %@", result);
    // }];
}

// 开启IPv6解析结果
- (IBAction)onIPv6Result:(id)sender {
    [_service enableIPv6:YES];
    // 开启持久化缓存
    [_service setCachedIPEnabled:YES];
}

// 开启IPv6解析链路
- (IBAction)onIPv6Resolve:(id)sender {
//    [_service enableIPv6Service:YES];
}

// 解析域名，返回IPv6解析结果
- (IBAction)onStartIPv6Resolve:(id)sender {
    NSString *host = @"ipv6.sjtu.edu.cn";
    NSString *IP = [_service getIPv6ByHostAsync:host];
    [self showAlert:@"IPv6解析结果" content:IP];
}

- (IBAction)onIPv6Test:(id)sender {
    TestIPv6ViewController *vc = [[TestIPv6ViewController alloc] init];
    [self presentViewController:vc animated:YES completion:nil];
}

// IPv6 Stack检测
- (IBAction)onCheckIPv6Stack:(id)sender {
}



- (void)testConcurrentResolveIPv4Hosts {
    for (NSString *ipv4Host in ipv4HostArray) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [_service getIpByHostAsync:ipv4Host];
        });
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        sleep(60);
        for (NSString *ipv4Host in ipv4HostArray) {
            NSString *ip = [_service getIpByHostAsync:ipv4Host];
            NSLog(@"resolve v4 result: [%@] - [%@]", ipv4Host, ip);
        }
    });
}

- (void)testConcurrentResolveIPv6Hosts {
    for (NSString *ipv6Host in ipv6HostArray) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [_service getIpByHostAsync:ipv6Host];
        });
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        sleep(60);
        for (NSString *ipv6Host in ipv6HostArray) {
            NSString *ip = [_service getIPv6ByHostAsync:ipv6Host];
            NSLog(@"resolve v6 result: [%@] - [%@]", ipv6Host, ip);
        }
    });
    NSString *originStr = @"origin";
    NSString *resStr = [NSString stringWithFormat:@"%@-%@", originStr, nil];
    NSLog(@"resStr: %@", resStr);
    resStr = [NSString stringWithFormat:@"%@-%@", originStr, @"test"];
    NSLog(@"resStr: %@", resStr);
    
    _logHandler = [[MyLoggerHandler alloc] init];
    printf("aaaa retain count = %ld\n", CFGetRetainCount((__bridge CFTypeRef)(_logHandler)));
    [_service setLogHandler:_logHandler];
    printf("bbbb retain count = %ld\n", CFGetRetainCount((__bridge CFTypeRef)(_logHandler)));
}

- (long long)currentTimeInMillis {
    NSTimeInterval time = [[NSDate date] timeIntervalSince1970];
    /* 单位：毫秒 */
    long long milliSecond = (long long)(time * 1000);
    return milliSecond;
}

- (IBAction)onResolveIP:(id)sender {
    NSString *host = @"www.aliyun.com";
    NSString *ip = [_service getIpByHostAsync:host];
    [self showAlert:@"resolve" content:[NSString stringWithFormat:@"ip: %@", ip]];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)showAlert:(NSString *)title content:(NSString *)content {
    if ([NSThread isMainThread]) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:content delegate:self cancelButtonTitle:@"已阅" otherButtonTitles:nil, nil];
        [alertView show];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:content delegate:self cancelButtonTitle:@"已阅" otherButtonTitles:nil, nil];
            [alertView show];
        });
    }
}

- (IBAction)queryIpv4:(id)sender {
    NSString *ipv4 = [_service getIpByHostAsync:@"www.taobao.com"];
    NSLog(@"ipv4:--------%@", ipv4);
}



- (IBAction)queryIpv6:(id)sender {
    NSString *ipv6 = [_service getIPv6ByHostAsync:@"www.taobao.com"];
    NSLog(@"ipv6:--------%@", ipv6);
}

- (IBAction)queryIpv4_Ipv6:(id)sender {
    
    NSDictionary *ipvsDic = [_service getIPv4_v6ByHostAsync:@"www.taobao.com"];
    NSLog(@"ipv4:--------%@++++ipv4:--------%@",[ipvsDic objectForKey:ALICLOUDHDNS_IPV4], [ipvsDic objectForKey:ALICLOUDHDNS_IPV6]);
    
    //预加载
    
    //AlicloudHttpDNS_IPTypeV4,           //ipv4
    //AlicloudHttpDNS_IPTypeV6,           //ipv6
    //AlicloudHttpDNS_IPTypeV64,          //ipv4 + ipv6
    
//    [_service setPreResolveHosts:@[@"www.taobao.com", @"www.tmall.com"] queryIPType: AlicloudHttpDNS_IPTypeV64];
//    [_service.requestScheduler addPreResolveHosts:@[@"www.taobao.com", @"www.tmall.com"] queryType:HttpdnsQueryIPTypeAuto];
}


@end
