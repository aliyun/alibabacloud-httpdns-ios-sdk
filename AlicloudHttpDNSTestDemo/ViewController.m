//
//  ViewController.m
//  AlicloudHttpDNSTestDemo
//
//  Created by junmo on 2018/8/3.
//  Copyright © 2018年 alibaba-inc.com. All rights reserved.
//

#import "ViewController.h"
#import "HttpdnsServiceProvider.h"

@interface ViewController ()

@property (nonatomic, strong) HttpDnsService *service;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _service = [[HttpDnsService alloc] autoInit];
    [_service setLogEnabled:YES];
    [_service setHTTPSRequestEnabled:YES];
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
