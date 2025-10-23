//
//  DemoHttpdnsScenario.m
//  AlicloudHttpDNSTestDemo
//
//  @author Created by Claude Code on 2025-10-23
//

#import "DemoHttpdnsScenario.h"
#import "DemoConfigLoader.h"

@interface DemoHttpdnsScenarioConfig ()
@end

@implementation DemoHttpdnsScenarioConfig

- (instancetype)init {
    if (self = [super init]) {
        _host = @"www.aliyun.com";
        _ipType = HttpdnsQueryIPTypeBoth;
        _httpsEnabled = YES;
        _persistentCacheEnabled = YES;
        _reuseExpiredIPEnabled = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    DemoHttpdnsScenarioConfig *cfg = [[[self class] allocWithZone:zone] init];
    cfg.host = self.host;
    cfg.ipType = self.ipType;
    cfg.httpsEnabled = self.httpsEnabled;
    cfg.persistentCacheEnabled = self.persistentCacheEnabled;
    cfg.reuseExpiredIPEnabled = self.reuseExpiredIPEnabled;
    return cfg;
}

@end

@interface DemoHttpdnsScenario () <HttpdnsLoggerProtocol, HttpdnsTTLDelegate>

@property (nonatomic, strong) HttpDnsService *service;
@property (nonatomic, strong) DemoHttpdnsScenarioConfig *config;
@property (nonatomic, strong) NSMutableString *logBuffer;
@property (nonatomic, strong) dispatch_queue_t logQueue;

@end

@implementation DemoHttpdnsScenario

- (instancetype)initWithDelegate:(id<DemoHttpdnsScenarioDelegate>)delegate {
    if (self = [super init]) {
        _delegate = delegate;
        _model = [[DemoResolveModel alloc] init];
        _config = [[DemoHttpdnsScenarioConfig alloc] init];
        _logBuffer = [NSMutableString string];
        _logQueue = dispatch_queue_create("com.alicloud.httpdns.demo.log", DISPATCH_QUEUE_SERIAL);
        [self buildService];
        [self applyConfig:_config];
    }
    return self;
}

- (void)buildService {
    DemoConfigLoader *cfg = [DemoConfigLoader shared];
    if (cfg.hasValidAccount) {
        if (cfg.aesSecretKey.length > 0) {
            self.service = [[HttpDnsService alloc] initWithAccountID:cfg.accountID secretKey:cfg.secretKey aesSecretKey:cfg.aesSecretKey];
        } else {
            self.service = [[HttpDnsService alloc] initWithAccountID:cfg.accountID secretKey:cfg.secretKey];
        }
    } else {
        self.service = [HttpDnsService sharedInstance];
    }
    [self.service setLogEnabled:YES];
    [self.service setNetworkingTimeoutInterval:8];
    [self.service setDegradeToLocalDNSEnabled:YES];
    self.service.ttlDelegate = self;
    [self.service setLogHandler:self];
}

- (void)applyConfig:(DemoHttpdnsScenarioConfig *)config {
    self.config = [config copy];
    self.model.host = self.config.host;
    self.model.ipType = self.config.ipType;
    [self.service setHTTPSRequestEnabled:self.config.httpsEnabled];
    [self.service setPersistentCacheIPEnabled:self.config.persistentCacheEnabled];
    [self.service setReuseExpiredIPEnabled:self.config.reuseExpiredIPEnabled];
}

- (void)resolveSyncNonBlocking {
    NSString *queryHost = [self currentHost];
    HttpdnsQueryIPType ipType = self.config.ipType;
    NSTimeInterval startMs = [[NSDate date] timeIntervalSince1970] * 1000.0;
    HttpdnsResult *result = [self.service resolveHostSyncNonBlocking:queryHost byIpType:ipType];
    [self handleResult:result host:queryHost ipType:ipType start:startMs];
}

- (void)resolveSync {
    NSString *queryHost = [self currentHost];
    HttpdnsQueryIPType ipType = self.config.ipType;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTimeInterval startMs = [[NSDate date] timeIntervalSince1970] * 1000.0;
        HttpdnsResult *result = [self.service resolveHostSync:queryHost byIpType:ipType];
        [self handleResult:result host:queryHost ipType:ipType start:startMs];
    });
}

- (NSString *)logSnapshot {
    __block NSString *snapshot = @"";
    dispatch_sync(self.logQueue, ^{
        snapshot = [self.logBuffer copy];
    });
    return snapshot;
}

- (NSString *)currentHost {
    return self.config.host.length > 0 ? self.config.host : @"www.aliyun.com";
}

- (void)handleResult:(HttpdnsResult *)result host:(NSString *)host ipType:(HttpdnsQueryIPType)ipType start:(NSTimeInterval)startMs {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.model.host = host;
        self.model.ipType = ipType;
        [self.model updateWithResult:result startTimeMs:startMs];
        id<DemoHttpdnsScenarioDelegate> delegate = self.delegate;
        if (delegate != nil) {
            [delegate scenario:self didUpdateModel:self.model];
        }
    });
}

- (void)log:(NSString *)logStr {
    if (logStr.length == 0) {
        return;
    }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], logStr];
    // 使用串行队列保证日志追加与快照的一致性
    dispatch_async(self.logQueue, ^{
        [self.logBuffer appendString:line];
        id<DemoHttpdnsScenarioDelegate> delegate = self.delegate;
        if (delegate != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate scenario:self didAppendLogLine:line];
            });
        }
    });
}

- (int64_t)httpdnsHost:(NSString *)host ipType:(AlicloudHttpDNS_IPType)ipType ttl:(int64_t)ttl {
    return ttl;
}

@end
