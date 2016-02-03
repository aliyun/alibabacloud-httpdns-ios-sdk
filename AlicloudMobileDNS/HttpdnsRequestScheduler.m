/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#import "HttpdnsModel.h"
#import "HttpdnsRequest.h"
#import "HttpdnsRequestScheduler.h"
#import "HttpdnsConfig.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"

@implementation HttpdnsRequestScheduler {
    BOOL _isExpiredIPEnabled;
    NSMutableDictionary *_hostManagerDict;
    dispatch_queue_t _syncDispatchQueue;
    NSOperationQueue *_asyncOperationQueue;
}

-(instancetype)init {
    if (self = [super init]) {
        _isExpiredIPEnabled = NO;
        _syncDispatchQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.sync", NULL);
        _asyncOperationQueue = [[NSOperationQueue alloc] init];
        [_asyncOperationQueue setMaxConcurrentOperationCount:MAX_REQUEST_THREAD_NUM];
        _hostManagerDict = [[NSMutableDictionary alloc] init];
    }
    return self;
}

-(void)readCachedHosts:(NSDictionary *)hosts {
    if (hosts) {
        dispatch_async(_syncDispatchQueue, ^{
            if ([_hostManagerDict count] != 0) {
                HttpdnsLogDebug(@"hostManager is not empty when reading cache from disk.");
                return;
            }
            long long currentTime = [HttpdnsUtil currentEpochTimeInSecond];
            for (NSString *key in [hosts allKeys]) {
                HttpdnsHostObject *hostObject = [hosts objectForKey:key];
                if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                    HttpdnsLogDebug(@"Can't handle more than %d hosts due to the software configuration.", MAX_MANAGE_HOST_NUM);
                    break;
                }
                if ([hostObject getIps] == nil || [[hostObject getIps] count] == 0) {
                    continue;
                }
                if (currentTime - [hostObject getLastLookupTime] > MAX_KEEPALIVE_PERIOD_FOR_CACHED_HOST && [hostObject getLastLookupTime] + [hostObject getTTL] > currentTime) {
                    continue;
                }
                if ([hostObject getState] == HttpdnsHostStateQuerying) {
                    [hostObject setState:HttpdnsHostStateValid];
                }
                [_hostManagerDict setObject:hostObject forKey:key];
                HttpdnsLogDebug(@"Set %@ for %@", hostObject, key);
            }
        });
    }
}

-(void)addPreResolveHosts:(NSArray *)hosts {
    dispatch_async(_syncDispatchQueue, ^{
        for (NSString *hostName in hosts) {
            if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                HttpdnsLogDebug(@"Can't handle more than %d hosts due to the software configuration.", MAX_MANAGE_HOST_NUM);
                break;
            }
            HttpdnsHostObject *hostObject = [_hostManagerDict objectForKey:hostName];
            if (hostObject &&
                (![hostObject isExpired] || [hostObject getState] == HttpdnsHostStateQuerying)
                ) {
                HttpdnsLogDebug(@"%@ is omitted, expired: %d state: %ld", hostName, [hostObject isExpired], (long)[hostObject getState]);
                continue;
            }
            hostObject = [[HttpdnsHostObject alloc] init];
            [hostObject setHostName:hostName];
            [hostObject setState:HttpdnsHostStateQuerying];
            [_hostManagerDict setObject:hostObject forKey:hostName];
            [self executeRequest:hostName synchronously:NO retryCount:0];
            HttpdnsLogDebug("Add host %@ and do async lookup.", hostName);
        }
    });
}

-(HttpdnsHostObject *)addSingleHostAndLookup:(NSString *)host synchronously:(BOOL)sync {
    __block HttpdnsHostObject *result = nil;
    __block BOOL needToQuery = NO;
    dispatch_sync(_syncDispatchQueue, ^{
        result = [_hostManagerDict objectForKey:host];
        HttpdnsLogDebug(@"Get from cache: %@", result);
        if (result == nil) {
            HttpdnsLogDebug("No available cache for %@ yet.", host);
            if ([_hostManagerDict count] > MAX_MANAGE_HOST_NUM) {
                HttpdnsLogDebug(@"Can't handle more than %d hosts due to the software configuration.", MAX_MANAGE_HOST_NUM);
                return;
            }
            result = [[HttpdnsHostObject alloc] init];
            [result setHostName:host];
            [result setState:HttpdnsHostStateInitialized];
            [_hostManagerDict setObject:result forKey:host];
            needToQuery = YES;
        } else if ([result getState] == HttpdnsHostStateInitialized) {
            HttpdnsLogDebug("%@ is just initialized", host);
            needToQuery = YES;
        } else if ([result isExpired]) {
            HttpdnsLogDebug("%@ record is expired, currentState: %ld", host, (long)[result getState]);
            if (_isExpiredIPEnabled) {
                needToQuery = NO;
                if ([result getState] != HttpdnsHostStateQuerying) {
                    [result setState:HttpdnsHostStateQuerying];
                    [self executeRequest:host synchronously:NO retryCount:0];
                }
            } else {
                // We still send a synchronous request even it is in QUERYING state in order to avoid HOL blocking.
                needToQuery = YES;
                result = nil;
            }
        }
        if (needToQuery) {
            [result setState:HttpdnsHostStateQuerying];
        }
    });
    if (needToQuery) {
        if (sync) return [self executeRequest:host synchronously:YES retryCount:0];
        else [self executeRequest:host synchronously:NO retryCount:0];
    }
    return [result getState] != HttpdnsHostStateInitialized ? result : nil;
}


-(void)mergeLookupResultToManager:(HttpdnsHostObject *)result forHost:(NSString *)host {
    if (result) {
        NSString *hostName = [result getHostName];
        HttpdnsHostObject * old = [_hostManagerDict objectForKey:hostName];
        [old setTTL:[result getTTL]];
        [old setLastLookupTime:[result getLastLookupTime]];
        [old setIps:[result getIps]];
        [old setState:HttpdnsHostStateValid];
        HttpdnsLogDebug("update %@: %@", hostName, result);
    } else {
        HttpdnsHostObject * hostObject = [_hostManagerDict objectForKey:host];
        [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
        [hostObject setTTL:30];
        [hostObject setIps:nil];
        [hostObject setState:HttpdnsHostStateValid];
        HttpdnsLogDebug("Can't resolve %@", host);
    }
    [HttpdnsLocalCache writeToLocalCache:_hostManagerDict];
}

-(HttpdnsHostObject *)executeRequest:(NSString *)host synchronously:(BOOL)sync retryCount:(int)hasRetryedCount {
    if (hasRetryedCount > MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogDebug("Retry count exceed limit, abort!");
        dispatch_async(_syncDispatchQueue, ^{
            [self mergeLookupResultToManager:nil forHost:host];
        });
        return nil;
    }
    if (sync) {
        HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
        NSError *error;
        HttpdnsLogDebug("Sync request for %@ starts.", host);
        HttpdnsHostObject *result = [request lookupHostFromServer:host error:&error];
        if (error) {
            HttpdnsLogDebug("Sync request for %@ error: %@", host, error);
            return [self executeRequest:host synchronously:YES retryCount:hasRetryedCount + 1];
        } else {
            dispatch_async(_syncDispatchQueue, ^{
                HttpdnsLogDebug("Sync request for %@ finishes.", host);
                [self mergeLookupResultToManager:result forHost:host];
            });
            return result;
        }
    } else {
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
            HttpdnsRequest *request = [[HttpdnsRequest alloc] init];
            NSError *error;
            HttpdnsLogDebug("Async request for %@ starts...", host);
            HttpdnsHostObject *result = [request lookupHostFromServer:host error:&error];
            if (error) {
                HttpdnsLogDebug("Async request for %@ error: %@", host, error);
                [self executeRequest:host synchronously:NO retryCount:hasRetryedCount + 1];
            } else {
                dispatch_sync(_syncDispatchQueue, ^{
                    HttpdnsLogDebug("Async request for %@ finishes.", host);
                    [self mergeLookupResultToManager:result forHost:host];
                });
            }
        }];
        [_asyncOperationQueue addOperation:operation];
        return nil;
    }
}


-(void)setExpiredIPEnabled:(BOOL)enable {
    _isExpiredIPEnabled = enable;
}
@end
