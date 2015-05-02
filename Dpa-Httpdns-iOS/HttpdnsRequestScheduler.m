//
//  HttpdnsRequestScheduler.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsRequestScheduler.h"
#import "HttpdnsConfig.h"
#import "HttpdnsUtil.h"

@interface DnsRquestOperation : NSOperation

@property (nonatomic, strong) NSString *queryHostsStringParam;

-(instancetype)initWithHostsStringParam:(NSString *)hostsString;
-(void)main;

@end

@implementation HttpdnsRequestScheduler

-(instancetype)initWithCacheHosts:(NSMutableDictionary *)hosts {
    dispatch_sync(_syncQueue, ^{
        [_hostManagerDict addEntriesFromDictionary:hosts];
    });
    _asyncQueue = [[NSOperationQueue alloc] init];
    [_asyncQueue setMaxConcurrentOperationCount:2];
    return self;
}

-(void)addPreResolveHosts:(NSArray *)hosts {
    dispatch_sync(_syncQueue, ^{
        for (NSString *hostName in hosts) {
            if ([_hostManagerDict objectForKey:hostName] == nil) {
                continue;
            }
            HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] initWithHostName:hostName
                                                                                inState:QUERYING];
            [_hostManagerDict setObject:hostObject forKey:hostName];
            [_lookupQueue addObject:hostName];
        }
        [self immediatelyExecuteTheLookupAction];
    });
}

-(HttpdnsHostObject *)addSingleHostAndLookup:(NSString *)host {
    __block HttpdnsHostObject *result = nil;
    dispatch_sync(_syncQueue, ^{
        if ([_lookupQueue count] == 0) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:1
                                             target:self
                                           selector:@selector(waitSometimeAndExecuteLookup)
                                           userInfo:nil
                                            repeats:NO];
        }
        result = [_hostManagerDict objectForKey:host];
        if (!result) {
            HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] initWithHostName:host
                                                                                inState:QUERYING];
            [_hostManagerDict setObject:hostObject forKey:host];
            [_lookupQueue addObject:host];
        }
        if ([result isExspired] && [result getState] != QUERYING) {
            [result setState:QUERYING];
            [_lookupQueue addObject:[result getHostName]];
        }
        [self tryToExecuteTheLookupAction];
    });
    return result;
}

// 用查询得到的结果更新Manager中管理着的域名
-(void)mergeLookupResultToManager:(NSMutableArray *)result {

}

// 一个域名单独被添加时，等待一秒钟看看随后有没有别的域名要查询，合并为一个查询
// 这期间如果添加的域名超过五个，会立即开始查询
-(void)waitSometimeAndExecuteLookup {
    dispatch_sync(_syncQueue, ^{
        if ([_lookupQueue count] > 0) {
            [self immediatelyExecuteTheLookupAction];
        }
    });
}

// 尝试执行域名查询，如果正在等待查询的域名超过阈值，则启动查询
-(void)tryToExecuteTheLookupAction {
    if ([_lookupQueue count] < MIN_HOST_NUM_PER_REQEUST) {
        return;
    }
    if (_timer && [_timer isValid]) {
        [_timer invalidate];
    }
    [self immediatelyExecuteTheLookupAction];
}

// 立即将等待查询对列里的域名组装，执行查询
-(void)immediatelyExecuteTheLookupAction {
    while ([_lookupQueue count] > 0) {
        NSMutableArray *hostsToLookup = [[NSMutableArray alloc] init];
        for (int i = 0; i < MIN_HOST_NUM_PER_REQEUST && [_lookupQueue count] > 0; i++) {
            [hostsToLookup addObject:[_lookupQueue firstObject]];
            [_lookupQueue removeObjectAtIndex:0];
        }
        NSString *requestHostStringParam = [hostsToLookup componentsJoinedByString:@","];
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
            @autoreleasepool {
                HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
                NSMutableArray *result = [request lookupALLHostsFromServer:requestHostStringParam];
                dispatch_sync(_syncQueue, ^{
                    [self mergeLookupResultToManager:result];
                });
            }
        }];
        [_asyncQueue addOperation:operation];
    }
}

@end
