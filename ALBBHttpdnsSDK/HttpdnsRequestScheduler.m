//
//  HttpdnsRequestScheduler.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsModel.h"
#import "HttpdnsRequest.h"
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsConfig.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"

static NSMutableDictionary *retryMap = nil;

@implementation HttpdnsRequestScheduler

+(void)initialize {
    retryMap = [[NSMutableDictionary alloc] init];
}

-(instancetype)init {
    _syncQueue = dispatch_queue_create("com.alibaba.sdk.httpdns", NULL);
    _asyncQueue = [[NSOperationQueue alloc] init];
    [_asyncQueue setMaxConcurrentOperationCount:MAX_REQUEST_THREAD_NUM];
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
                HttpdnsLogError(@"[readCacheHosts] - Cant handle more than %d hosts", MAX_MANAGE_HOST_NUM);
                break;
            }
            if ([hostObject getIps] == nil || [[hostObject getIps] count] == 0) {
                continue;
            }
            if (currentTime - [hostObject getLastLookupTime] > 2 * 24 * 60 * 60) {
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
            long long originTTL = [hostObject getTTL];
            long long timeElapsed = [HttpdnsUtil currentEpochTimeInSecond] - [hostObject getLastLookupTime];
            if (timeElapsed > originTTL + MAX_EXPIRED_ENDURE_TIME_IN_SEC) {
                // 如果TTL已经过期太久，就改为最多一分钟后不合法
                [hostObject setTTL:(timeElapsed - (MAX_EXPIRED_ENDURE_TIME_IN_SEC - 1 * 60))];
            }
            [_hostManagerDict setObject:hostObject forKey:key];
            HttpdnsLogDebug(@"[readCacheHosts] - Set %@ for %@", hostObject, key);
        }
    });
}

-(void)addPreResolveHosts:(NSArray *)hosts {
    dispatch_sync(_syncQueue, ^{
        for (NSString *hostName in hosts) {
            if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                HttpdnsLogError(@"[addPreResolveHosts] - Cant handle more than %d hosts", MAX_MANAGE_HOST_NUM);
                break;
            }
            HttpdnsHostObject *hostObject = [_hostManagerDict objectForKey:hostName];
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
    __block BOOL directlyReturn = YES;
    dispatch_sync(_syncQueue, ^{
        BOOL needToQuery = NO;
        result = [_hostManagerDict objectForKey:host];
        HttpdnsLogDebug(@"Get from cache: %@", result);
        if (result == nil) {
            directlyReturn = NO;
            HttpdnsLogDebug(@"[addSingleHostAndLookUp] - %@ haven't exist in cache yet", host);
            if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                HttpdnsLogError(@"[addSingleHostAndLookup] - Cant handle more than %d hosts", MAX_MANAGE_HOST_NUM);
                return;
            }
            result = [[HttpdnsHostObject alloc] init];
            [result setHostName:host];
            [result setState:INITIALIZE];
            [_hostManagerDict setObject:result forKey:host];
            needToQuery = YES;
        }
        else if ([result isExpired]) {
            HttpdnsLogDebug(@"[addSingleHostAndLookUp] - %@ is expired, currentState: %ld", host, (long)[result getState]);
            if ([result getState] != QUERYING) {
                needToQuery = YES;
            }
            if ([result isAlreadyUnawailable]) {
                directlyReturn = NO;
            }
        }
        else if ([result getState] == INITIALIZE) {
            HttpdnsLogDebug(@"[addSingleHostAndLookUp] - %@ is initialize", host);
            needToQuery = YES;
            directlyReturn = NO;
        }

        if (needToQuery) {
            // 一个域名单独被添加时，等待一段时间看看随后有没有别的域名要查询，合并为一个查询
            // 这期间如果添加的域名超过五个，会立即开始查询
            [_lookupQueue addObject:host];
            [result setState:QUERYING];
            if ([_lookupQueue count] == 1) {
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FIRST_QEURY_WAIT_INTERVAL_IN_SEC * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
                    [self arrivalTimeAndExecuteLookup];
                });
            }
            HttpdnsLogDebug(@"[addSingleHostAndLookUp] - no other querys waiting, start timer and wait");
            [self tryToExecuteTheLookupAction];
        }
    });
    return directlyReturn == YES ? result : nil;
}

// 用查询得到的结果更新Manager中管理着的域名，需要在同步队列中执行
-(void)mergeLookupResultToManager:(NSArray *)result forHosts:(NSArray *)hosts {
    NSMutableArray * noResolveResultHosts = [[NSMutableArray alloc] initWithArray:hosts];
    if (result) {
        for (HttpdnsHostObject *hostObject in result) {
            NSString *hostName = [hostObject getHostName];
            HttpdnsHostObject * old = [_hostManagerDict objectForKey:hostName];
            [old setTTL:[hostObject getTTL]];
            [old setLastLookupTime:[hostObject getLastLookupTime]];
            [old setIps:[hostObject getIps]];
            [old setState:VALID];

            [noResolveResultHosts removeObject:hostName];
            HttpdnsLogDebug(@"[mergeLookupResult] - update %@", hostName);
        }
    }
    for (NSString * host in noResolveResultHosts) {
        HttpdnsHostObject * hostObject = [_hostManagerDict objectForKey:host];
        [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
        [hostObject setTTL:30];
        [hostObject setIps:nil];
        [hostObject setState:VALID];
        HttpdnsLogDebug(@"[mergeLookupResult] - can't resolve %@", host);
    }
    [HttpdnsLocalCache writeToLocalCache:_hostManagerDict];
}

-(void)arrivalTimeAndExecuteLookup {
    dispatch_sync(_syncQueue, ^{
        if ([_lookupQueue count] > 0) {
            HttpdnsLogDebug(@"[arrivalTimeAndExecuteLookup] - %lu host to query", (unsigned long)[_lookupQueue count]);
            [self immediatelyExecuteTheLookupAction];
        }
    });
}

// 尝试执行域名查询，如果正在等待查询的域名超过阈值，则启动查询，需要在同步队列中执行
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
-(void)executeALookupActionWithHosts:(NSArray *)hosts retryCount:(int)count {
    if (count > MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogError(@"[executeLookup] - Retry time exceed limit, abort!");
        [HttpdnsRequest notifyRequestFailed];
        dispatch_sync(_syncQueue, ^{
            [self mergeLookupResultToManager:nil forHosts:hosts];
        });
        return;
    }
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        NSError *error;
        HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
        HttpdnsLogDebug(@"[executeLookup] - Request start, request string: %@", hosts);
        NSString * resolveHostString = [hosts componentsJoinedByString:@","];
        NSMutableArray *result = [request lookupAllHostsFromServer:resolveHostString error:&error];
        if (error) {
            HttpdnsLogError(@"[executeLookup] - error: %@", error);
            [self executeALookupActionWithHosts:hosts retryCount:count + 1];
            return;
        } else {
            dispatch_sync(_syncQueue, ^{
                HttpdnsLogDebug(@"[executeLookup] - Request finish, merge %lu data to Manager", (unsigned long)[result count]);
                [self mergeLookupResultToManager:result forHosts:hosts];
            });
        }
    }];
    [_asyncQueue addOperation:operation];
}

// 立即将等待查询对列里的域名组装，执行查询，需要在同步队列中执行
-(void)immediatelyExecuteTheLookupAction {
    HttpdnsLogDebug(@"[immedatelyExecute] - Total query cnt: %lu", (unsigned long)[_lookupQueue count]);
    while ([_lookupQueue count] > 0) {
        NSMutableArray *hostsToLookup = [[NSMutableArray alloc] init];
        for (int i = 0; i < MIN_HOST_NUM_PER_REQEUST && [_lookupQueue count] > 0; i++) {
            [hostsToLookup addObject:[_lookupQueue firstObject]];
            [_lookupQueue removeObjectAtIndex:0];
        }
        [self executeALookupActionWithHosts:hostsToLookup retryCount:0];
    }
}

-(HttpdnsHostObject *)addSingleHostAndLookupSync:(NSString *)host {
    __block BOOL needToQuery = false;
    __block HttpdnsHostObject * result = nil;
    dispatch_sync(_syncQueue, ^{
        result = [_hostManagerDict objectForKey:host];
        HttpdnsLogDebug(@"Get from cache: %@", result);
        if (result == nil) {
            HttpdnsLogDebug(@"[addSingleHostAndLookUpSync] - %@ haven't exist in cache yet", host);
            if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                HttpdnsLogError(@"[addSingleHostAndLookupSync] - Cant handle more than %d hosts", MAX_MANAGE_HOST_NUM);
                return;
            }
            result = [[HttpdnsHostObject alloc] init];
            [result setHostName:host];
            [result setState:INITIALIZE];
            [_hostManagerDict setObject:result forKey:host];
            needToQuery = YES;
        } else if ([result isExpired]) {
            HttpdnsLogDebug(@"[addSingleHostAndLookUpSync] - %@ is expired, currentState: %ld", host, (long)[result getState]);
            if ([result getState] != QUERYING) {
                needToQuery = YES;
            }
        } else if ([result getState] == INITIALIZE) {
            HttpdnsLogDebug(@"[addSingleHostAndLookUpSync] - %@ is initialize", host);
            needToQuery = YES;
        }
        if (needToQuery) {
            [result setState: QUERYING];
        }
    });
    if (needToQuery) {
        return [self syncRequest:host retryCount:0];
    }
    long long waitTotalInUS = 0;
    while ([result getState] == QUERYING && waitTotalInUS < 10 * 1000 * 1000) {
        usleep(50 * 1000);
        waitTotalInUS += 50 * 1000;
    }
    return result;
}

-(HttpdnsHostObject *)syncRequest:(NSString *)host retryCount:(int)hasRetryedCount {
    NSArray *hosts = [[NSArray alloc] initWithObjects:host, nil];
    if (hasRetryedCount > MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogError(@"[executeLookup] - Retry time exceed limit, abort!");
        [HttpdnsRequest notifyRequestFailed];
        [self mergeLookupResultToManager:nil forHosts:hosts];
        return nil;
    }
    NSError *error;
    HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
    HttpdnsLogDebug(@"[executeLookup] - Request start, request string: %@", hosts);
    NSString * resolveHostString = [hosts componentsJoinedByString:@","];
    NSMutableArray *result = [request lookupAllHostsFromServer:resolveHostString error:&error];
    if (error == nil) {
        dispatch_sync(_syncQueue, ^{
            HttpdnsLogDebug(@"[executeLookup] - Request finish, merge %lu data to Manager", (unsigned long)[result count]);
            [self mergeLookupResultToManager:result forHosts:hosts];
        });
        return result && [result count] > 0 ? result[0] : nil;
    } else {
        HttpdnsLogError(@"[syncRequest] - error: %@", error);
        return [self syncRequest:host retryCount:hasRetryedCount + 1];
    }
}

-(void)resetAfterNetworkChanged {
    dispatch_sync(_syncQueue, ^{
        for (NSString * key in [_hostManagerDict allKeys]) {
            HttpdnsHostObject * hostObject = [_hostManagerDict objectForKey:key];
            [hostObject setState: INITIALIZE];
        }
    });
}
@end
