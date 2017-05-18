//
//  HttpdnsIPRecord.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsIPRecord.h"

@interface HttpdnsIPRecord()

@property (nonatomic, assign) NSUInteger hostRecordId;
@property (nonatomic, copy) NSString *IP;
@property (nonatomic, assign) int64_t TTL;

@end

@implementation HttpdnsIPRecord

- (instancetype)initWithHostRecordId:(NSUInteger)hostRecordId IP:(NSString *)IP TTL:(int64_t)TTL {
    if (self = [super init]) {
        _hostRecordId = hostRecordId;
        _IP = [IP copy];
        _TTL = TTL;
    }
    return self;
}

+ (instancetype)IPRecordWithHostRecordId:(NSUInteger)hostRecordId IP:(NSString *)IP TTL:(int64_t)TTL {
    HttpdnsIPRecord *IPRecord = [[HttpdnsIPRecord alloc] initWithHostRecordId:hostRecordId IP:IP TTL:TTL];
    return IPRecord;
}

- (instancetype)initWithIP:(NSString *)IP {
    return [self initWithHostRecordId:0 IP:IP TTL:0];
}

+ (instancetype)IPRecordWithIP:(NSString *)IP {
    return [self IPRecordWithHostRecordId:0 IP:IP TTL:0];
}

@end
