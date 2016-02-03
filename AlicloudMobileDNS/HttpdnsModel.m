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
#import "HttpdnsConfig.h"
#import "HttpdnsUtil.h"
#import "HttpdnsLog.h"


@implementation HttpdnsIpObject

-(id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        self.ip = [aDecoder decodeObjectForKey:@"ip"];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.ip forKey:@"ip"];
}

-(NSString *)description {
    return self.ip;
}

@end

@implementation HttpdnsHostObject

-(instancetype)init {
    _hostName = nil;
    _currentState = HttpdnsHostStateInitialized;
    _lastLookupTime = 0;
    _ttl = -1;
    _ips = nil;
    return self;
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _hostName = [aDecoder decodeObjectForKey:@"hostName"];
        _lastLookupTime = [aDecoder decodeInt64ForKey:@"lastLookupTime"];
        _ttl = [aDecoder decodeInt64ForKey:@"ttl"];
        _ips = [aDecoder decodeObjectForKey:@"ips"];
        _currentState = [aDecoder decodeIntegerForKey:@"currentState"];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_hostName forKey:@"hostName"];
    [aCoder encodeInt64:_lastLookupTime forKey:@"lastLookupTime"];
    [aCoder encodeInt64:_ttl forKey:@"ttl"];
    [aCoder encodeObject:_ips forKey:@"ips"];
    [aCoder encodeInteger:_currentState forKey:@"currentState"];
}

-(BOOL)isExpired {
    long long currentEpoch = (long long)[[[NSDate alloc] init] timeIntervalSince1970];
    if (_lastLookupTime + _ttl < currentEpoch) {
        return YES;
    }
    return NO;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"Host = %@ ips = %@ lastLookup = %lld ttl = %lld state = %ld",
            _hostName, _ips, _lastLookupTime, _ttl, (long)_currentState];
}

@end

static NSString *localCacheKey = @"httpdns_hostManagerData";
static long long lastWroteToCacheTime = 0;
static long long minimalIntervalInSecond = 60;

@implementation HttpdnsLocalCache

+(void)writeToLocalCache:(NSDictionary *)allHostObjectsInManagerDict {
    long long currentTime = [HttpdnsUtil currentEpochTimeInSecond];
    if (currentTime - lastWroteToCacheTime < minimalIntervalInSecond) {
        HttpdnsLogDebug("Write too often, abort this writing.");
        return;
    }
    lastWroteToCacheTime = currentTime;
    NSData *buffer = [NSKeyedArchiver archivedDataWithRootObject:allHostObjectsInManagerDict];
    NSData *encodedBuffer = [buffer base64EncodedDataWithOptions:kNilOptions];
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    [userDefault setObject:encodedBuffer forKey:localCacheKey];
    [userDefault synchronize];
    HttpdnsLogDebug("Write %lu to local file system.", (unsigned long)(unsigned long)[allHostObjectsInManagerDict count]);
}

+(NSDictionary *)readFromLocalCache {
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    NSData *buffer = [userDefault objectForKey:localCacheKey];
    if (buffer) {
        NSData *decodedBuffer = [[NSData alloc] initWithBase64EncodedData:buffer options:kNilOptions];
        NSDictionary *dict = [NSKeyedUnarchiver unarchiveObjectWithData:decodedBuffer];
        HttpdnsLogDebug("Read %lu from local file system: %@.", (unsigned long)[dict count], dict);
        return dict;
    } else {
        return nil;
    }
}

+(void)cleanLocalCache {
    HttpdnsLogDebug("Clean cache.");
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    [userDefault removeObjectForKey:localCacheKey];
    [userDefault synchronize];
}
@end