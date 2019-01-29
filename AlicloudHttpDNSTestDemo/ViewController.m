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

#import <AlicloudUtils/AlicloudIPv6Adapter.h>

NSArray *ipv4HostArray = nil;
NSArray *ipv6HostArray = nil;

@interface ViewController ()

@property (nonatomic, strong) HttpDnsService *service;
@property (nonatomic, strong) HttpdnsScheduleCenter *sc;
@property (nonatomic, strong) MyLoggerHandler *logHandler;

@end

@implementation ViewController

- (IBAction)onHost1:(id)sender {
    [_service getIpByHostAsync:@"www.aliyun.com"];
    
    NSString *sessionId = [_service getSessionId];
    NSLog(@"Get sessionId: %@", sessionId);
}

- (IBAction)onHost2:(id)sender {
    for (NSString *ipv4Host in ipv4HostArray) {
        NSString *ipRes = [_service getIpByHostAsync:ipv4Host];
        NSLog(@"host: %@, ip: %@", ipv4Host, ipRes);
    }
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

// IPv6 Stack检测
- (IBAction)onCheckIPv6Stack:(id)sender {
//    NSString *preResolveIP = @"106.11.90.200";
//    BOOL haveIPv6Stack = [_service haveIPv6Stack];
//    if (haveIPv6Stack) {
//        NSString *ipv6 = [[AlicloudIPv6Adapter getInstance] getIPv6Address:preResolveIP];
//        [self showAlert:@"IPv6地址转换" content:ipv6];
//    }
//    NSMutableDictionary *mDic = [NSMutableDictionary dictionary];
//    [mDic setObject:@(1) forKey:@"enable"];
//    NSLog(@"mDic: %@", mDic);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _service = [[HttpDnsService alloc] autoInit];
    [_service setLogEnabled:YES];
    [_service enableIPv6:YES];
    
//    for (int i = 0; i < 100; i++) {
//        dispatch_async(dispatch_queue_create(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//            NSString *sessionId = [HttpdnsUtil generateSessionID];
//            if ([HttpdnsUtil isValidString:sessionId]) {
//                NSLog(@"thread: %@, sessionId: %@, address: %p", [NSThread currentThread], sessionId, sessionId);
//            }
//        });
//    }
    
//    NSArray *ips = @[
//                     @"www.163.com",
//                     @"www.douban.com",
//                     @"data.zhibo8.cc",
//                     @"www.12306.cn",
//                     @"t.yunjiweidian.com",
//                     @"dca.qiumibao.com",
//                     @"home.cochat.lenovo.com",
//                     @"ra.namibox.com",
//                     @"namibox.com",
//                     @"dou.bz"
//                     ];
//
//
//    long long start, end;
//
//    for (NSString *ip in ips) {
//        start = [self currentTimeInMillis];
//        [_service getIpByHostAsyncInURLFormat:ip];
//        end = [self currentTimeInMillis];
//        NSLog(@"duration: %lld", end - start);
//    }
    _sc = [HttpdnsScheduleCenter sharedInstance];
//    [_service setLogEnabled:YES];
//    [_service setHTTPSRequestEnabled:YES];
    
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
    
    [self testConcurrentResolveIPv4Hosts];
    [self testConcurrentResolveIPv6Hosts];
    
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

- (IBAction)onBeaconDisable:(id)sender {
    [_sc setSDKDisableFromBeacon];
    [self showAlert:@"beacon" content:@"set sdk disable"];
}

- (IBAction)onBeaconEnable:(id)sender {
    [_sc clearSDKDisableFromBeacon];
    [self showAlert:@"beacon" content:@"set sdk enable"];
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

@end
