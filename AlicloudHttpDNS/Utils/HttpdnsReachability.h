//
//  HttpdnsCacheStore.m
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

/**
 * Does ARC support GCD objects?
 * It does if the minimum deployment target is iOS 6+ or Mac OS X 8+
 *
 * @see http://opensource.apple.com/source/libdispatch/libdispatch-228.18/os/object.h
 **/
#if OS_OBJECT_USE_OBJC
#define NEEDS_DISPATCH_RETAIN_RELEASE 0
#else
#define NEEDS_DISPATCH_RETAIN_RELEASE 1
#endif

/**
 * Create NS_ENUM macro if it does not exist on the targeted version of iOS or OS X.
 *
 * @see http://nshipster.com/ns_enum-ns_options/
 **/
#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

extern NSString *const kHttpdnsReachabilityChangedNotification;

typedef NS_ENUM(NSInteger, HttpdnsNetworkStatus) {
    // Apple NetworkStatus Compatible Names.
    HttpdnsNotReachable = 0,
    HttpdnsReachableViaWWAN = 1,
    HttpdnsReachableViaWiFi = 2
};

@class HttpdnsReachability;

typedef void (^HttpdnsNetworkReachable)(HttpdnsReachability * reachability);
typedef void (^HttpdnsNetworkUnreachable)(HttpdnsReachability * reachability);

@interface HttpdnsReachability : NSObject

@property (nonatomic, copy) HttpdnsNetworkReachable    reachableBlock;
@property (nonatomic, copy) HttpdnsNetworkUnreachable  unreachableBlock;


@property (nonatomic, assign) BOOL reachableOnWWAN;

+ (HttpdnsReachability*)reachabilityWithHostname:(NSString*)hostname;
// This is identical to the function above, but is here to maintain
//compatibility with Apples original code. (see .m)
+ (HttpdnsReachability*)reachabilityWithHostName:(NSString*)hostname;
+ (HttpdnsReachability*)reachabilityForInternetConnection;
+ (HttpdnsReachability*)reachabilityWithAddress:(const struct sockaddr_in*)hostAddress;
+ (HttpdnsReachability*)reachabilityForLocalWiFi;

- (HttpdnsReachability *)initWithReachabilityRef:(SCNetworkReachabilityRef)ref;

- (BOOL)startNotifier;
- (void)stopNotifier;

- (BOOL)isReachable;
- (BOOL)isReachableViaWWAN;
- (BOOL)isReachableViaWiFi;

// WWAN may be available, but not active until a connection has been established.
// WiFi may require a connection for VPN on Demand.
- (BOOL)isConnectionRequired; // Identical DDG variant.
- (BOOL)connectionRequired; // Apple's routine.
// Dynamic, on demand connection?
- (BOOL)isConnectionOnDemand;
// Is user intervention required?
- (BOOL)isInterventionRequired;

- (HttpdnsNetworkStatus)currentReachabilityStatus;
- (SCNetworkReachabilityFlags)reachabilityFlags;
- (NSString*)currentReachabilityString;
- (NSString*)currentReachabilityFlags;

@end
