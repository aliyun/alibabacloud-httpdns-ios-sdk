//
//  DemoHttpdnsScenario.h
//  AlicloudHttpDNSTestDemo
//
//  @author Created by Claude Code on 2025-10-23
//

#import <Foundation/Foundation.h>
#import "DemoResolveModel.h"
#import "HttpdnsService.h"

NS_ASSUME_NONNULL_BEGIN

@class DemoHttpdnsScenario;

@interface DemoHttpdnsScenarioConfig : NSObject <NSCopying>

@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) HttpdnsQueryIPType ipType;
@property (nonatomic, assign) BOOL httpsEnabled;
@property (nonatomic, assign) BOOL persistentCacheEnabled;
@property (nonatomic, assign) BOOL reuseExpiredIPEnabled;

- (instancetype)init;

@end

@protocol DemoHttpdnsScenarioDelegate <NSObject>

- (void)scenario:(DemoHttpdnsScenario *)scenario didUpdateModel:(DemoResolveModel *)model;
- (void)scenario:(DemoHttpdnsScenario *)scenario didAppendLogLine:(NSString *)line;

@end

@interface DemoHttpdnsScenario : NSObject

@property (nonatomic, weak, nullable) id<DemoHttpdnsScenarioDelegate> delegate;
@property (nonatomic, strong, readonly) DemoResolveModel *model;

- (instancetype)initWithDelegate:(id<DemoHttpdnsScenarioDelegate>)delegate;
- (void)applyConfig:(DemoHttpdnsScenarioConfig *)config;
- (void)resolveSyncNonBlocking;
- (void)resolveSync;
- (NSString *)logSnapshot;

@end

NS_ASSUME_NONNULL_END

