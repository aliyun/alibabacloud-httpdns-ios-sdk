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

@interface ViewController ()

@property (nonatomic, strong) HttpDnsService *service;
@property (nonatomic, strong) HttpdnsScheduleCenter *sc;
@property (nonatomic, strong) MyLoggerHandler *logHandler;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    for (int i = 0; i < 100; i++) {
        dispatch_async(dispatch_queue_create(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *sessionId = [HttpdnsUtil generateSessionID];
            if ([HttpdnsUtil isValidString:sessionId]) {
                NSLog(@"thread: %@, sessionId: %@, address: %p", [NSThread currentThread], sessionId, sessionId);
            }
        });
    }
    
    NSArray *ips = @[
                     @"www.163.com",
                     @"www.douban.com",
                     @"data.zhibo8.cc",
                     @"www.12306.cn",
                     @"t.yunjiweidian.com",
                     @"dca.qiumibao.com",
                     @"home.cochat.lenovo.com",
                     @"ra.namibox.com",
                     @"namibox.com",
                     @"dou.bz"
                     ];

//    NSArray *ips = @[ @"gateway.vtechl1.com" ];
    
    _service = [[HttpDnsService alloc] autoInit];
    _sc = [HttpdnsScheduleCenter sharedInstance];
//    [_service setLogEnabled:YES];
//    [_service setHTTPSRequestEnabled:YES];
    
    long long start, end;
    
    for (NSString *ip in ips) {
        start = [self currentTimeInMillis];
        [_service getIpByHostAsyncInURLFormat:ip];
        end = [self currentTimeInMillis];
        NSLog(@"duration: %lld", end - start);
    }
    
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

- (IBAction)onHost1:(id)sender {
    [_service getIpByHostAsync:@"www.aliyun.com"];
    
    NSString *sessionId = [_service getSessionId];
    NSLog(@"Get sessionId: %@", sessionId);
}

- (IBAction)onHost2:(id)sender {
    
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
