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
@property (nonatomic, copy) NSString *region;

@end

@implementation HttpdnsIPRecord

- (instancetype)initWithHostRecordId:(NSUInteger)hostRecordId IP:(NSString *)IP TTL:(int64_t)TTL region:(NSString *)region{
    if (self = [super init]) {
        _hostRecordId = hostRecordId;
        _IP = [IP copy];
        _TTL = TTL;
        _region = region;
    }
    return self;
}

+ (instancetype)IPRecordWithHostRecordId:(NSUInteger)hostRecordId IP:(NSString *)IP TTL:(int64_t)TTL region:(NSString *)region{
    HttpdnsIPRecord *IPRecord = [[HttpdnsIPRecord alloc] initWithHostRecordId:hostRecordId IP:IP TTL:TTL region:region];
    return IPRecord;
}

- (instancetype)initWithIP:(NSString *)IP region:(NSString *)region{
    return [self initWithHostRecordId:0 IP:IP TTL:0 region:region];
}

+ (instancetype)IPRecordWithIP:(NSString *)IP region:(NSString *)region{
    return [self IPRecordWithHostRecordId:0 IP:IP TTL:0 region:region];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"{\n ip: %@\n}\n", _IP];
}

@end
