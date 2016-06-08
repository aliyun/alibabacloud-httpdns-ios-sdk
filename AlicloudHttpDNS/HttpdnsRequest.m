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

#import "HttpdnsServiceProvider.h"
#import "HttpdnsModel.h"
#import "HttpdnsRequest.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"
#import "HttpdnsConfig.h"
#import "AlicloudUtils/AlicloudUtils.h"

#ifndef DEBUG
NSString * const ALICLOUD_HTTPDNS_SERVER_IP = @"203.107.1.1";
NSString * const ALICLOUD_HTTPDNS_SERVER_PORT = @"80";
#else
NSString * const ALICLOUD_HTTPDNS_SERVER_IP = @"10.125.65.207";
NSString * const ALICLOUD_HTTPDNS_SERVER_PORT = @"8100";
#endif

@implementation HttpdnsRequest

#pragma mark init

-(instancetype)init {
    return self;
}

#pragma mark LookupIpAction

-(HttpdnsHostObject *)parseHostInfoFromHttpResponse:(NSDictionary *)json {
    if (json == nil) {
        return nil;
    }
    NSString *hostName = [json objectForKey:@"host"];
    NSArray *ips = [json objectForKey:@"ips"];
    if (ips == nil || [ips count] == 0) {
        HttpdnsLogDebug("IP list is empty for host %@", hostName);
        return nil;
    }
    NSMutableArray *ipArray = [[NSMutableArray alloc] init];
    for (NSString *ip in ips) {
        HttpdnsIpObject *ipObject = [[HttpdnsIpObject alloc] init];
        // Adapt to IPv6-only network.
        [ipObject setIp:[[AlicloudIPv6Adapter getInstance] handleIpv4Address:ip]];
        [ipArray addObject:ipObject];
    }
    HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
    [hostObject setHostName:hostName];
    [hostObject setIps:ipArray];
    [hostObject setTTL:[[json objectForKey:@"ttl"] longLongValue]];
    [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
    [hostObject setQueryingState:NO];
    HttpdnsLogDebug("Parsed host: %@ ttl: %lld ips: %@", [hostObject getHostName], [hostObject getTTL], ipArray);
    return hostObject;
}

-(NSMutableURLRequest *)constructRequestWith:(NSString *)hostsString {
    HttpDnsService *sharedService = [HttpDnsService sharedInstance];
    NSString *serverIp = ALICLOUD_HTTPDNS_SERVER_IP;
    // Adapt to IPv6-only network.
    if ([[AlicloudIPv6Adapter getInstance] isIPv6OnlyNetwork]) {
        serverIp = [NSString stringWithFormat:@"[%@]", [[AlicloudIPv6Adapter getInstance] handleIpv4Address:ALICLOUD_HTTPDNS_SERVER_IP]];
    }
    NSString *url = [NSString stringWithFormat:@"http://%@:%@/%d/d?host=%@",
                     serverIp, ALICLOUD_HTTPDNS_SERVER_PORT, sharedService.accountID, hostsString];
    HttpdnsLogDebug("Request URL: %@", url);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:url]
                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                  timeoutInterval:REQUEST_TIMEOUT_INTERVAL];
    return request;
}

-(HttpdnsHostObject *)lookupHostFromServer:(NSString *)hostString error:(NSError **)error {
    HttpdnsLogDebug("Resolve host(%@) over network.", hostString);
    NSMutableURLRequest *request = [self constructRequestWith:hostString];
    NSHTTPURLResponse *response;
    NSData *result = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error];

    // 异常交由上层处理
    if (*error) {
        HttpdnsLogDebug("Network error: %@", *error);
        return nil;
    } else {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:result options:kNilOptions error:error];
        if ([response statusCode] != 200) {
            HttpdnsLogDebug("ReponseCode %ld.", (long)[response statusCode]);
            if (*error) {
                NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                      @"Response code not 200, and parse response message error", @"ErrorMessage",
                                      [NSString stringWithFormat:@"%d", (int) [response statusCode]], @"ResponseCode", nil];
                *error = [[NSError alloc] initWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10002 userInfo:dict];
                return nil;
            }
            NSString *errCode = [json objectForKey:@"code"];
            NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  errCode, @"ErrorMessage", nil];
            *error = [[NSError alloc] initWithDomain:@"httpdns.request.lookupAllHostsFromServer" code:10003 userInfo:dict];
            return nil;
        } else {
            HttpdnsLogDebug("Response code 200.");
            return [self parseHostInfoFromHttpResponse:json];
        }
    }
}

@end