//
//
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/4/11.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#ifndef HttpDnsHitService_h
#define HttpDnsHitService_h

@interface HttpDnsHitService : NSObject
//
+ (void)setGlobalProperty;
//
+ (void)disableHitService;
//
+ (void)bizActiveHit;
//
+ (void)bizSnifferWithHost:(NSString *)host
              srvAddrIndex:(NSInteger)srvAddrIndex;

+ (void)bizLocalDisableWithHost:(NSString *)host
                   srvAddrIndex:(NSInteger)srvAddrIndex;

//
+ (void)bizCacheEnable:(BOOL)enable;
//
+ (void)bizExpiredIpEnable:(BOOL)enable;
//
+ (void)bizhErrScWithScAddr:(NSString *)scAddr
                    errCode:(NSInteger)errCode
                     errMsg:(NSString *)errMsg;
//
+ (void)bizErrSrvWithSrvAddrIndex:(NSInteger)srvAddrIndex
                     errCode:(NSInteger)errCode
                      errMsg:(NSString *)errMsg;
//
+ (void)bizContinuousBootingCrashWithLog:(NSString *)log;

//
+ (void)bizRunningCrashWithLog:(NSString *)log;
//
+ (void)bizUncaughtExceptionWithException:(NSString *)exception;

//
+ (void)bizPerfScWithScAddr:(NSString *)scAddr
                       cost:(NSString *)cost;
//
+ (void)bizPerfSrcWithScAddr:(NSString *)scAddr
                        cost:(NSString *)cost;

//
+ (void)bizPerfGetIPWithHost:(NSString *)host
                     success:(BOOL)success
                   cacheOpen:(BOOL)cacheOpen;

@end

#endif /* HttpDnsHitService_h */
