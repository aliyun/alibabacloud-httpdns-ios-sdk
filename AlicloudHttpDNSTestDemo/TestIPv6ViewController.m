//
//  TestIPv6ViewController.m
//  AlicloudHttpDNSTestDemo
//
//  Created by junmo on 2019/2/26.
//  Copyright © 2019年 alibaba-inc.com. All rights reserved.
//

#import "TestIPv6ViewController.h"
#import <AlicloudUtils/AlicloudUtils.h>
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsService.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsHostRecord.h"
#import "HttpdnsHostCacheStore.h"

NSString *ipv6Host = @"ipv6.sjtu.edu.cn";
NSString *testIPv4 = @"202.120.2.47";
NSString *testIPv6 = @"2001:da8:8000:1:0:0:0:80";

@interface TestIPv6ViewController ()

@property (nonatomic, strong) UIButton *button1;
@property (nonatomic, strong) UIButton *button2;
@property (nonatomic, strong) UIButton *button3;
@property (nonatomic, strong) UIButton *button4;
@property (nonatomic, strong) UIButton *button5;
@property (nonatomic, strong) UIButton *button6;
@property (nonatomic, strong) UIButton *button7;
@property (nonatomic, strong) UIButton *button8;
@property (nonatomic, strong) UIButton *button9;
@property (nonatomic, strong) UIButton *button10;
@property (nonatomic, strong) UIButton *button11;
@property (nonatomic, strong) UIButton *button12;
@property (nonatomic, strong) UIButton *button13;
@property (nonatomic, strong) UIButton *button14;

@property (nonatomic, strong) HttpDnsService *service;
@property (nonatomic, strong) HttpdnsRequestScheduler *scheduler;
@property (nonatomic, strong) HttpdnsHostCacheStore *hostCacheStore;

@end

@implementation TestIPv6ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    CGFloat xStart = 50;
    CGFloat yStart = 100;
    CGFloat yInterval = 50;
    CGFloat width = 200;
    CGFloat height = 40;
    
    _button1 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button1.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button1.backgroundColor = [UIColor blackColor];
    _button1.tintColor = [UIColor whiteColor];
    [_button1 setTitle:@"Show Memory Cache" forState:UIControlStateNormal];
    [_button1 addTarget:self action:@selector(showMemoryCache) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button1];
    
    _button2 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button2.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button2.backgroundColor = [UIColor blackColor];
    _button2.tintColor = [UIColor whiteColor];
    [_button2 setTitle:@"Show DB Cache" forState:UIControlStateNormal];
    [_button2 addTarget:self action:@selector(showDBCache) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button2];
    
    _button3 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button3.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button3.backgroundColor = [UIColor blackColor];
    _button3.tintColor = [UIColor whiteColor];
    [_button3 setTitle:@"IPv4 Resolve" forState:UIControlStateNormal];
    [_button3 addTarget:self action:@selector(resolveV4) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button3];
    
    _button4 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button4.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button4.backgroundColor = [UIColor blackColor];
    _button4.tintColor = [UIColor whiteColor];
    [_button4 setTitle:@"IPv6 Resolve" forState:UIControlStateNormal];
    [_button4 addTarget:self action:@selector(resolveV6) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button4];
    
    _button5 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button5.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button5.backgroundColor = [UIColor blackColor];
    _button5.tintColor = [UIColor whiteColor];
    [_button5 setTitle:@"加载持久化缓存到内存" forState:UIControlStateNormal];
    [_button5 addTarget:self action:@selector(loadDBCache) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button5];
    
    _button6 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button6.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button6.backgroundColor = [UIColor blackColor];
    _button6.tintColor = [UIColor whiteColor];
    [_button6 setTitle:@"删除内存和持久化缓存" forState:UIControlStateNormal];
    [_button6 addTarget:self action:@selector(clearAllCache) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button6];
    
    _button7 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button7.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button7.backgroundColor = [UIColor blackColor];
    _button7.tintColor = [UIColor whiteColor];
    [_button7 setTitle:@"插入有效v4缓存" forState:UIControlStateNormal];
    [_button7 addTarget:self action:@selector(addValidV4) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button7];
    
    _button8 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button8.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button8.backgroundColor = [UIColor blackColor];
    _button8.tintColor = [UIColor whiteColor];
    [_button8 setTitle:@"插入有效v6缓存" forState:UIControlStateNormal];
    [_button8 addTarget:self action:@selector(addValidV6) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button8];
    
    _button9 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button9.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button9.backgroundColor = [UIColor blackColor];
    _button9.tintColor = [UIColor whiteColor];
    [_button9 setTitle:@"插入有效v4+v6缓存" forState:UIControlStateNormal];
    [_button9 addTarget:self action:@selector(addValidV4AndV6) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button9];
    
    _button10 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button10.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button10.backgroundColor = [UIColor blackColor];
    _button10.tintColor = [UIColor whiteColor];
    [_button10 setTitle:@"插入过期v4缓存" forState:UIControlStateNormal];
    [_button10 addTarget:self action:@selector(addExpiredV4) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button10];
    
    _button11 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button11.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button11.backgroundColor = [UIColor blackColor];
    _button11.tintColor = [UIColor whiteColor];
    [_button11 setTitle:@"插入过期v6缓存" forState:UIControlStateNormal];
    [_button11 addTarget:self action:@selector(addExpiredV6) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button11];
    
    _button12 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _button12.frame = CGRectMake(xStart, yStart += yInterval, width, height);
    _button12.backgroundColor = [UIColor blackColor];
    _button12.tintColor = [UIColor whiteColor];
    [_button12 setTitle:@"插入过期v4+v6缓存" forState:UIControlStateNormal];
    [_button12 addTarget:self action:@selector(addExpiredV4AndV6) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:_button12];
    
    [self.view setBackgroundColor:[UIColor whiteColor]];
    
    _service = [[HttpDnsService sharedInstance] initWithAccountID:102933];
    _scheduler = _service.requestScheduler;
    [_service setLogEnabled:YES];
    _hostCacheStore = [[HttpdnsHostCacheStore alloc] init];
}

- (void)showMemoryCache {
    NSString *memoryCache = [_scheduler showMemoryCache];
    [self showAlert:@"MemoryCache" content:memoryCache];
}

- (void)showDBCache {
    NSString *dbCache = [_hostCacheStore showDBCache];
    [self showAlert:@"DBCache" content:dbCache];
}

- (void)resolveV4 {
    [_service setCachedIPEnabled:YES];
    NSString *ipv4 = [_service getIpByHostAsync:ipv6Host];
    [self showAlert:@"IPv4解析" content:ipv4];
}

- (void)resolveV6 {
    [_service setCachedIPEnabled:YES];
    NSString *ipv6 = [_service getIPv6ByHostAsync:ipv6Host];
    [self showAlert:@"IPv6解析" content:ipv6];
}

- (void)loadDBCache {
    [_service setCachedIPEnabled:YES];
}

- (void)clearAllCache {
    [_scheduler cleanAllHostMemoryCache];
    [_hostCacheStore deleteHostRecordAndItsIPsWithHost:ipv6Host];
}

- (void)addValidV4 {
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:ipv6Host IPs:@[ testIPv4 ] IP6s:@[] TTL:3600 ipRegion:@"" ip6Region:@""];
    [_hostCacheStore insertHostRecords:@[ hostRecord ]];
}

- (void)addValidV6 {
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:ipv6Host IPs:@[] IP6s:@[ testIPv6 ] TTL:3600 ipRegion:@"" ip6Region:@""];
    [_hostCacheStore insertHostRecords:@[ hostRecord ]];
}

- (void)addValidV4AndV6 {
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:ipv6Host IPs:@[ testIPv4 ] IP6s:@[ testIPv6 ] TTL:3600 ipRegion:@"" ip6Region:@""];
    [_hostCacheStore insertHostRecords:@[ hostRecord ]];
}

- (void)addExpiredV4 {
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:ipv6Host IPs:@[ testIPv4 ] IP6s:@[] TTL:0 ipRegion:@"" ip6Region:@""];
    [_hostCacheStore insertHostRecords:@[ hostRecord ]];
}

- (void)addExpiredV6 {
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:ipv6Host IPs:@[ ] IP6s:@[ testIPv6 ] TTL:0 ipRegion:@"" ip6Region:@""];
    [_hostCacheStore insertHostRecords:@[ hostRecord ]];
}

- (void)addExpiredV4AndV6 {
    HttpdnsHostRecord *hostRecord = [HttpdnsHostRecord hostRecordWithHost:ipv6Host IPs:@[ testIPv4 ] IP6s:@[ testIPv6 ] TTL:0 ipRegion:@"" ip6Region:@""];
    [_hostCacheStore insertHostRecords:@[ hostRecord ]];
}

- (void)showAlert:(NSString *)title content:(NSString *)content {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:content preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alertController addAction:okAction];
    
    if ([NSThread isMainThread]) {
        [self presentViewController:alertController animated:YES completion:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alertController animated:YES completion:nil];
        });
    }
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
