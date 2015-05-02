//
//  HttpdnsRequest.m
//  Dpa-Httpdns-iOS
//
//  Created by zhouzhuo on 5/1/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import "HttpdnsRequest.h"
#import "HttpdnsUtil.h"

NSString * const HTTPDNS_SERVER_IP = @"10.125.65.207:8100";
NSString * const HTTPDNS_VERSION_NUM = @"1";
NSString * const HTTPDNS_APPID = @"123456";
NSString * const HTTPDNS_ACCESSKEYID = @"httpdnstest";
NSString * const HTTPDNS_ACCESSKEYSECRET = @"hello";

@implementation HttpdnsRequest

#pragma mark init

-(instancetype)init {
    return self;
}

#pragma mark LookupIpAction

-(NSMutableArray *)parseHostInfoFromHttpResponse:(NSData *)body {
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:kNilOptions error:&error];
    if (!json) {
        return nil;
    }
    NSArray *dnss = [json objectForKey:@"dns"];
    for (NSDictionary *dict in dnss) {
        NSArray *ips = [dict objectForKey:@"ips"];
        NSMutableArray *ipNums = [[NSMutableArray alloc] init];
        for (NSDictionary *ipDict in ips) {
            [ipNums addObject:[ipDict objectForKey:@"ip"]];
        }
        HttpdnsHostObject *hostObject = [[HttpdnsHostObject alloc] init];
        [hostObject setHostName:[dict objectForKey:@"host"]];
        [hostObject setIps:ipNums];
        [hostObject setTTL:[[dict objectForKey:@"ttl"] longLongValue]];
        [hostObject setLastLookupTime:[HttpdnsUtil currentEpochTimeInSecond]];
        [hostObject setState:VALID];
        [result addObject:hostObject];
    }
    return result;
}

-(NSMutableURLRequest *)constructRequestWith:(NSString *)hostsString {
    NSString *timestamp = [HttpdnsUtil currentEpochTimeInSecondString];
    NSString *url = [NSString stringWithFormat:@"http://%@/resolve?host=%@&version=%@&appid=%@&timestamp=%@",
                     HTTPDNS_SERVER_IP, hostsString, HTTPDNS_VERSION_NUM, HTTPDNS_APPID, timestamp];
    NSString *contentToSign = [NSString stringWithFormat:@"%@%@%@%@",
                               HTTPDNS_VERSION_NUM, HTTPDNS_APPID, timestamp, hostsString];
    NSString *signature = [NSString stringWithFormat:@"HTTPDNS %@:%@",
                           HTTPDNS_ACCESSKEYID,
                           [HttpdnsUtil HMACSha1Sign:[contentToSign dataUsingEncoding:NSUTF8StringEncoding] withKey:HTTPDNS_ACCESSKEYSECRET]];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[[NSURL alloc] initWithString:url]];
    [request setHTTPMethod:@"GET"];
    [request setValue:signature forHTTPHeaderField:@"Authorization"];

    [HttpdnsLog LogD:@"contentToSign: %@", contentToSign];
    [HttpdnsLog LogD:@"signature: %@", signature];

    return request;
}

-(NSMutableArray *)lookupALLHostsFromServer:(NSString *)hostsString {
    NSMutableURLRequest *request = [self constructRequestWith:hostsString];

    NSError *error;
    NSURLResponse *response;
    NSData *result = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    if (error) {
        return nil;
    }

    return [self parseHostInfoFromHttpResponse:result];
}

@end
