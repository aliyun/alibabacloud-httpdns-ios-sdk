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
+ (void)setGlobalPropertyWithAccountId:(NSString *)accountId;
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

+ (void)hitSCTimeWithSuccess:(BOOL)success
                 methodStart:(NSDate *)methodStart
                         url:(NSString *)url;

//+ (void)bizPerfScWithScAddr:(NSString *)scAddr
//                       cost:(NSString *)cost;
//
//+ (void)bizPerfSrcWithSrvAddr:(NSString *)srvAddr
//                        cost:(NSString *)cost;
+ (void)hitSRVTimeWithSuccess:(BOOL)success
                  methodStart:(NSDate *)methodStart
                          url:(NSString *)url;

//
+ (void)bizPerfGetIPWithHost:(NSString *)host
                     success:(BOOL)success
                   cacheOpen:(BOOL)cacheOpen;

+ (void)bizPerfUserGetIPWithHost:(NSString *)host
                         success:(BOOL)success
                       cacheOpen:(BOOL)cacheOpen;

+ (void)bizIPSelectionWithHost:(NSString *)host
                     defaultIp:(NSString *)defaultIp
                    selectedIp:(NSString *)selectedIp
                 defaultIpCost:(NSNumber *)defaultIpCost
                selectedIpCost:(NSNumber *)selectedIpCost
                       ipCount:(NSNumber *)ipCount;

@end

#endif /* HttpDnsHitService_h */
