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
#import "HttpdnsLocalCache.h"
#import "HttpdnsModel.h"

static NSMutableDictionary *retryMap = nil;

@implementation HttpdnsRequestScheduler

+(void)initialize {
    retryMap = [[NSMutableDictionary alloc] init];
}

-(instancetype)init {
    _syncQueue = dispatch_queue_create("com.alibaba.sdk.httpdns", NULL);
    _asyncQueue = [[NSOperationQueue alloc] init];
    [_asyncQueue setMaxConcurrentOperationCount:MAX_REQEUST_THREAD_NUM];
    _lookupQueue = [[NSMutableArray alloc] init];
    _hostManagerDict = [[NSMutableDictionary alloc] init];
    return self;
}

-(void)readCacheHosts:(NSDictionary *)hosts {
    dispatch_sync(_syncQueue, ^{
        if ([_hostManagerDict count] != 0) {
            // 不是初始化状态，本地缓存读取到的数据不生效
            return;
        }
        long long currentTime = [HttpdnsUtil currentEpochTimeInSecond];
        for (NSString *key in [hosts allKeys]) {
            HttpdnsHostObject *hostObject = [hosts objectForKey:key];
            if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                // 如果全局字典中记录的host超过限制，不接受新域名
                HttpdnsLogError(@"[readCacheHosts] - Cant handle more than %d hosts", MAX_MANAGE_HOST_NUM);
                break;
            }
            if (currentTime - [hostObject getLastLookupTime] > 7 * 24 * 60 * 60) {
                // 如果这个域名离最后一次查询超过7天，舍弃这条缓存
                continue;
            }
            if ([hostObject getState] == QUERYING) {
                //如果state为QUERYING，调整为VALID或INITIALIZE
                if ([hostObject getIps] != nil) {
                    [hostObject setState:VALID];
                } else {
                    [hostObject setState:INITIALIZE];
                }
            }
            [_hostManagerDict setObject:hostObject forKey:key];
        }
    });
}

-(void)addPreResolveHosts:(NSArray *)hosts {
    dispatch_sync(_syncQueue, ^{
        for (NSString *hostName in hosts) {
            if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                // 如果全局字典中记录的host超过限制，不接受新域名
                HttpdnsLogError(@"[addPreResolveHosts] - Cant handle more than %d hosts", MAX_MANAGE_HOST_NUM);
                break;
            }
            HttpdnsHostObject *hostObject = [_hostManagerDict objectForKey:hostName];
            // 如果已经存在，且未过期或已经出于查询状态，则不继续添加
            if (hostObject &&
                (![hostObject isExpired] || [hostObject getState] == QUERYING)
                ) {
                HttpdnsLogDebug(@"[addPreResolveHosts] - %@ omit, is Expired?: %d state: %ld", hostName, [hostObject isExpired], (long)[hostObject getState]);
                continue;
            }

            hostObject = [[HttpdnsHostObject alloc] init];
            [hostObject setHostName:hostName];
            [hostObject setState:QUERYING];
            [_hostManagerDict setObject:hostObject forKey:hostName];
            [_lookupQueue addObject:hostName];
            HttpdnsLogDebug(@"ManagerDict and lookupQueue add host %@", hostName);
        }
        [self immediatelyExecuteTheLookupAction];
    });
}

-(HttpdnsHostObject *)addSingleHostAndLookup:(NSString *)host {
    __block HttpdnsHostObject *result = nil;
    dispatch_sync(_syncQueue, ^{
        BOOL needToQuery = NO;
        result = [_hostManagerDict objectForKey:host];
        if (!result) {
            HttpdnsLogDebug(@"[addSingleHostAndLookUp] - %@ haven't exist in cache yet", host);
            if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                // 如果全局字典中记录的host超过限制，不接受新域名
                HttpdnsLogError(@"[addSingleHostAndLookup] - Cant handle more than %d hosts", MAX_MANAGE_HOST_NUM);
                return;
            }
            HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
            [hostObject setHostName:host];
            [_hostManagerDict setObject:hostObject forKey:host];
            needToQuery = YES;
        }
        if ([result isExpired] && [result getState] != QUERYING) {
            HttpdnsLogDebug(@"[addSingleHostAndLookUp] - %@ is expired", host);
            needToQuery = YES;
        }
        if ([result getState] == INITIALIZE) {
            HttpdnsLogDebug(@"[addSingleHostAndLookUp] - %@ is initialize", host);
            needToQuery = YES;
        }
        if (needToQuery && [_lookupQueue count] == 0) {
            // 一个域名单独被添加时，等待一段时间看看随后有没有别的域名要查询，合并为一个查询
            // 这期间如果添加的域名超过五个，会立即开始查询
            HttpdnsLogDebug(@"[addSingleHostAndLookUp] - no query waiting, start timer and wait");
            [_lookupQueue addObject:host];
            [result setState:QUERYING];
            _timer = [NSTimer scheduledTimerWithTimeInterval:FIRST_QEURY_WAIT_INTERVAL_IN_SEC
                                             target:self
                                           selector:@selector(arrivalTimeAndExecuteLookup)
                                           userInfo:nil
                                            repeats:NO];
        }
        [self tryToExecuteTheLookupAction];
    });
    return result;
}

// 用查询得到的结果更新Manager中管理着的域名，需要运行在同步块中
-(void)mergeLookupResultToManager:(NSMutableArray *)result {
    for (HttpdnsHostObject *hostObject in result) {
        NSString *hostName = [hostObject getHostName];
        [_hostManagerDict setObject:hostObject forKey:hostName];
        HttpdnsLogDebug(@"[mergeLookupResult] - update %@", hostName);
    }
    // 每次合并之后，写入本地文件缓存
    HttpdnsLogDebug(@"[mergeLookupResult] - %@", _hostManagerDict);
    [HttpdnsLocalCache writeToLocalCache:_hostManagerDict];
}

// 定时器到期，开始查询
-(void)arrivalTimeAndExecuteLookup {
    dispatch_sync(_syncQueue, ^{
        if ([_lookupQueue count] > 0) {
            HttpdnsLogDebug(@"[arrivalTimeAndExecuteLookup] - %lu host to query", (unsigned long)[_lookupQueue count]);
            [self immediatelyExecuteTheLookupAction];
        }
    });
}

// 尝试执行域名查询，如果正在等待查询的域名超过阈值，则启动查询，需要运行在同步块中
-(void)tryToExecuteTheLookupAction {
    if ([_lookupQueue count] < MIN_HOST_NUM_PER_REQEUST) {
        HttpdnsLogDebug(@"[tryToExecute] - waiting count not exceed %d", MIN_HOST_NUM_PER_REQEUST);
        return;
    }
    if (_timer && [_timer isValid]) {
        HttpdnsLogDebug(@"[tryToExecute] - waiting count exceed %d, start to query and cancel timer", MIN_HOST_NUM_PER_REQEUST);
        [_timer invalidate];
    }
    [self immediatelyExecuteTheLookupAction];
}

// 执行请求，失败会在此重试
-(void)executeALookupActionWithHosts:(NSString *)hosts retryCount:(int)count {
    if (count > MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogError(@"[executeLookup] - Retry time exceed limit, abort!");
        // 重试也没成功，记为一次请求失败
        [HttpdnsRequest notifyRequestFailed];
        return;
    }
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        NSError *error;
        HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
        HttpdnsLogDebug(@"[executeLookup] - Request start, request string: %@", hosts);
        NSMutableArray *result = [request lookupAllHostsFromServer:hosts error:&error];
        dispatch_sync(_syncQueue, ^{
            if (error) {
                [self executeALookupActionWithHosts:hosts retryCount:count + 1];
                return;
            }
            HttpdnsLogDebug(@"[executeLookup] - Request finish, merge %lu data to Manager", (unsigned long)[result count]);
            [self mergeLookupResultToManager:result];
        });
    }];
    [_asyncQueue addOperation:operation];
}

// 立即将等待查询对列里的域名组装，执行查询，需要运行在同步块中
-(void)immediatelyExecuteTheLookupAction {
    HttpdnsLogDebug(@"[immedatelyExecute] - Total query cnt: %lu", (unsigned long)[_lookupQueue count]);
    while ([_lookupQueue count] > 0) {
        NSMutableArray *hostsToLookup = [[NSMutableArray alloc] init];
        for (int i = 0; i < MIN_HOST_NUM_PER_REQEUST && [_lookupQueue count] > 0; i++) {
            [hostsToLookup addObject:[_lookupQueue firstObject]];
            [_lookupQueue removeObjectAtIndex:0];
        }
        NSString *requestHostStringParam = [hostsToLookup componentsJoinedByString:@","];
        [self executeALookupActionWithHosts:requestHostStringParam retryCount:0];
    }
}
@end
