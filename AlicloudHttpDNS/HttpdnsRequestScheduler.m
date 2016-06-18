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
#import "AlicloudUtils/AlicloudUtils.h"

@implementation HttpdnsRequestScheduler {
    long _lastNetworkStatus;
    BOOL _isExpiredIPEnabled;
    BOOL _isPreResolveAfterNetworkChangedEnabled;
    NSMutableDictionary *_hostManagerDict;
    dispatch_queue_t _syncDispatchQueue;
    NSOperationQueue *_asyncOperationQueue;
}

-(instancetype)init {
    if (self = [super init]) {
        _lastNetworkStatus = 0;
        _isExpiredIPEnabled = NO;
        _isPreResolveAfterNetworkChangedEnabled = NO;
        _syncDispatchQueue = dispatch_queue_create("com.alibaba.sdk.httpdns.sync", NULL);
        _asyncOperationQueue = [[NSOperationQueue alloc] init];
        [_asyncOperationQueue setMaxConcurrentOperationCount:MAX_REQUEST_THREAD_NUM];
        _hostManagerDict = [[NSMutableDictionary alloc] init];
        [AlicloudIPv6Adapter getInstance];
        [AlicloudReachabilityManager shareInstance];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(networkChanged:)
                                                     name:ALICLOUD_NETWOEK_STATUS_NOTIFY
                                                   object:nil];
    }
    return self;
}

-(void)addPreResolveHosts:(NSArray *)hosts {
    dispatch_async(_syncDispatchQueue, ^{
        for (NSString *hostName in hosts) {
            if ([self isHostsNumberLimitReached]) {
                break;
            }
            HttpdnsHostObject *hostObject = [_hostManagerDict objectForKey:hostName];
            if (hostObject) {
                if ([hostObject isExpired] && ![hostObject isQuerying]) {
                    HttpdnsLogDebug("%@ is expired, pre fetch again.", hostName);
                    [self executeRequest:hostName synchronously:NO retryCount:0];
                } else {
                    HttpdnsLogDebug(@"%@ is omitted, expired: %d querying: %d", hostName, [hostObject isExpired], [hostObject isQuerying]);
                    continue;
                }
            } else {
                [self executeRequest:hostName synchronously:NO retryCount:0];
                HttpdnsLogDebug("Pre resolve host %@ by async lookup.", hostName);
            }
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
            if ([self isHostsNumberLimitReached]) {
                return;
            }
            needToQuery = YES;
        } else if ([result isExpired]) {
            HttpdnsLogDebug("%@ is expired, queryingState: %d", host, [result isQuerying]);
            if (_isExpiredIPEnabled) {
                needToQuery = NO;
                if (![result isQuerying]) {
                    [result setQueryingState:YES];
                    [self executeRequest:host synchronously:NO retryCount:0];
                }
            } else {
                HttpdnsLogDebug("Expired IP is not accepted.");
                // For sync mode, We still send a synchronous request even it is in QUERYING state in order to avoid HOL blocking.
                needToQuery = YES;
                result = nil;
            }
        }
        if (needToQuery) {
            [result setQueryingState:YES];
        }
    });
    if (needToQuery) {
        if (sync) return [self executeRequest:host synchronously:YES retryCount:0];
        else [self executeRequest:host synchronously:NO retryCount:0];
    }
    return result;
}


-(void)mergeLookupResultToManager:(HttpdnsHostObject *)result forHost:(NSString *)host {
    if (result) {
        NSString *hostName = [result getHostName];
        HttpdnsHostObject * old = [_hostManagerDict objectForKey:hostName];
        if (old) {
            [old setTTL:[result getTTL]];
            [old setLastLookupTime:[result getLastLookupTime]];
            [old setIps:[result getIps]];
            [old setQueryingState:NO];
            HttpdnsLogDebug("Update %@: %@", hostName, result);
        } else {
            HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
            [hostObject setHostName:host];
            [hostObject setLastLookupTime:[result getLastLookupTime]];
            [hostObject setTTL:[result getTTL]];
            [hostObject setIps:[result getIps]];
            [hostObject setQueryingState:NO];
            HttpdnsLogDebug("New resolved item: %@: %@", host, result);
            [_hostManagerDict setObject:hostObject forKey:host];
        }
    } else {
        HttpdnsLogDebug("Can't resolve %@", host);
    }
}

-(HttpdnsHostObject *)executeRequest:(NSString *)host synchronously:(BOOL)sync retryCount:(int)hasRetryedCount {
    if (hasRetryedCount > MAX_REQUEST_RETRY_TIME) {
        HttpdnsLogDebug("Retry count exceed limit, abort!");
        dispatch_async(_syncDispatchQueue, ^{
            [self mergeLookupResultToManager:nil forHost:host];
        });
        return nil;
    }
    if (![AlicloudReport isDeviceReported:AMSHTTPDNS]) {
        [AlicloudReport statAsync:AMSHTTPDNS];
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

-(BOOL)isHostsNumberLimitReached {
    if ([_hostManagerDict count] >= MAX_MANAGE_HOST_NUM) {
        HttpdnsLogDebug(@"Can't handle more than %d hosts due to the software configuration.", MAX_MANAGE_HOST_NUM);
        return YES;
    }
    return NO;
}

-(void)setExpiredIPEnabled:(BOOL)enable {
    _isExpiredIPEnabled = enable;
}

- (void)setPreResolveAfterNetworkChanged:(BOOL)enable {
    _isPreResolveAfterNetworkChangedEnabled = enable;
}

- (void)networkChanged:(NSNotification *)notification {
    NSNumber *networkStatus = [notification object];
    __block NSString *statusString;
    switch ([networkStatus longValue]) {
        case 0:
            statusString = @"None";
            break;
        case 1:
            statusString = @"Wifi";
            break;
        case 3:
            statusString = @"3G";
            break;
        default:
            statusString = @"Unknown";
            break;
    }
    HttpdnsLogDebug(@"Network changed, status: %@(%ld), lastNetworkStatus: %ld", statusString, [networkStatus longValue], _lastNetworkStatus);
    if (_lastNetworkStatus != [networkStatus longValue]) {
        dispatch_async(_syncDispatchQueue, ^{
            if (![statusString isEqualToString:@"None"]) {
                NSArray * hostArray = [_hostManagerDict allKeys];
                [_hostManagerDict removeAllObjects];
                if (_isPreResolveAfterNetworkChangedEnabled == YES) {
                    HttpdnsLogDebug(@"Network changed, pre resolve for hosts: %@", hostArray);
                    [self addPreResolveHosts:hostArray];
                }
            }
        });
    }
    _lastNetworkStatus = [networkStatus longValue];
}

@end
