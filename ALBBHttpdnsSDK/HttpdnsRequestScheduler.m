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

@implementation HttpdnsRequestScheduler

-(instancetype)init {
    _syncQueue = dispatch_queue_create("com.alibaba.sdk.httpdns", NULL);
    _asyncQueue = [[NSOperationQueue alloc] init];
    [_asyncQueue setMaxConcurrentOperationCount:2];
    return self;
}

-(void)readCacheHosts:(NSDictionary *)hosts {
    dispatch_sync(_syncQueue, ^{
        // 不是初始化状态，本地缓存读取到的数据不生效
        if ([_hostManagerDict count] != 0) {
            return;
        }
        [_hostManagerDict addEntriesFromDictionary:hosts];
    });
}

-(void)addPreResolveHosts:(NSArray *)hosts {
    dispatch_sync(_syncQueue, ^{
        for (NSString *hostName in hosts) {
            HttpdnsHostObject *hostObject = [_hostManagerDict objectForKey:hostName];
            // 如果已经存在，且未过期或已经出于查询状态，则不继续添加
            if (hostObject &&
                (![hostObject isExpired] || [hostObject getState] != QUERYING)
                ) {
                continue;
            }

            hostObject = [[HttpdnsHostObject alloc] init];
            [hostObject setHostName:hostName];
            [hostObject setState:QUERYING];
            [_hostManagerDict setObject:hostObject forKey:hostName];
            [_lookupQueue addObject:hostName];
        }
        [self immediatelyExecuteTheLookupAction];
    });
}

-(HttpdnsHostObject *)addSingleHostAndLookup:(NSString *)host {
    __block HttpdnsHostObject *result = nil;
    dispatch_sync(_syncQueue, ^{
        // 一个域名单独被添加时，等待一段时间看看随后有没有别的域名要查询，合并为一个查询
        // 这期间如果添加的域名超过五个，会立即开始查询
        if ([_lookupQueue count] == 0) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:5
                                             target:self
                                           selector:@selector(arrivalTimeAndExecuteLookup)
                                           userInfo:nil
                                            repeats:NO];
        }
        result = [_hostManagerDict objectForKey:host];
        if (!result) {
            HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
            [hostObject setHostName:host];
            [hostObject setState:QUERYING];
            [_hostManagerDict setObject:hostObject forKey:host];
            [_lookupQueue addObject:host];
        }
        if ([result isExpired] && [result getState] != QUERYING) {
            [result setState:QUERYING];
            [_lookupQueue addObject:[result getHostName]];
        }
        // TODO 怎样判断快过期，快过期要更新
        [self tryToExecuteTheLookupAction];
    });
    return result;
}

// 用查询得到的结果更新Manager中管理着的域名，需要运行在同步块中
-(void)mergeLookupResultToManager:(NSMutableArray *)result {
    for (HttpdnsHostObject *hostObject in result) {
        NSString *hostName = [hostObject getHostName];
        [_hostManagerDict setObject:hostObject forKey:hostName];
    }
}

// 定时器到期，开始查询
-(void)arrivalTimeAndExecuteLookup {
    dispatch_sync(_syncQueue, ^{
        if ([_lookupQueue count] > 0) {
            [self immediatelyExecuteTheLookupAction];
        }
    });
}

// 尝试执行域名查询，如果正在等待查询的域名超过阈值，则启动查询，需要运行在同步块中
-(void)tryToExecuteTheLookupAction {
    if ([_lookupQueue count] < MIN_HOST_NUM_PER_REQEUST) {
        return;
    }
    if (_timer && [_timer isValid]) {
        [_timer invalidate];
    }
    [self immediatelyExecuteTheLookupAction];
}

// 立即将等待查询对列里的域名组装，执行查询，需要运行在同步块中
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
                NSError *error;
                HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
                NSMutableArray *result = [request lookupALLHostsFromServer:requestHostStringParam error:&error];
                if (error) {
                    // TODO 处理重试逻辑
                }
                dispatch_sync(_syncQueue, ^{
                    [self mergeLookupResultToManager:result];
                });
            }
        }];
        [_asyncQueue addOperation:operation];
    }
}

@end
