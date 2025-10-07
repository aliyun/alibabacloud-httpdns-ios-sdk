//
//  DemoConfigLoader.m
//  AlicloudHttpDNSTestDemo
//
//  @author Created by Claude Code on 2025-10-05
//

#import "DemoConfigLoader.h"

@implementation DemoConfigLoader {
    NSInteger _accountID;
    NSString *_secretKey;
    NSString *_aesSecretKey;
    BOOL _hasValidAccount;
}

+ (instancetype)shared {
    static DemoConfigLoader *loader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loader = [[DemoConfigLoader alloc] init];
    });
    return loader;
}

- (instancetype)init {
    if (self = [super init]) {
        [self loadConfig];
    }
    return self;
}

// 复杂逻辑：配置加载顺序为 Bundle > 环境变量；并对 accountID 进行有效性校验
- (void)loadConfig {
    _accountID = 0;
    _secretKey = @"";
    _aesSecretKey = @"";
    _hasValidAccount = NO;

    NSDictionary *bundleDict = nil;
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"DemoConfig" ofType:@"plist"];
    if (plistPath.length > 0) {
        bundleDict = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    }

    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSNumber *acc = bundleDict[@"accountID"]; // NSNumber preferred in plist
    NSString *secret = bundleDict[@"secretKey"] ?: @"";
    NSString *aes = bundleDict[@"aesSecretKey"] ?: @"";

    NSString *envAcc = env[@"HTTPDNS_ACCOUNT_ID"];
    NSString *envSecret = env[@"HTTPDNS_SECRET_KEY"];
    NSString *envAes = env[@"HTTPDNS_AES_SECRET_KEY"];

    if (envAcc.length > 0) {
        acc = @([envAcc integerValue]);
    }
    if (envSecret.length > 0) {
        secret = envSecret;
    }
    if (envAes.length > 0) {
        aes = envAes;
    }

    if (acc != nil && [acc integerValue] > 0 && secret.length > 0) {
        _accountID = [acc integerValue];
        _secretKey = secret;
        _aesSecretKey = aes ?: @"";
        _hasValidAccount = YES;
    } else {
        _accountID = 0;
        _secretKey = @"";
        _aesSecretKey = @"";
        _hasValidAccount = NO;
    }
}

- (NSInteger)accountID { return _accountID; }
- (NSString *)secretKey { return _secretKey; }
- (NSString *)aesSecretKey { return _aesSecretKey; }
- (BOOL)hasValidAccount { return _hasValidAccount; }

@end

