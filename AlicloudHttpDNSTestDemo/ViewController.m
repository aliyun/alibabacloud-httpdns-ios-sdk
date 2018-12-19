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

@interface ViewController ()

@property (nonatomic, strong) HttpDnsService *service;

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
    [_service setLogEnabled:YES];
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

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
