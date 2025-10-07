//
//  DemoConfigLoader.h
//  AlicloudHttpDNSTestDemo
//
//  @author Created by Claude Code on 2025-10-05
//

#import <Foundation/Foundation.h>

@interface DemoConfigLoader : NSObject

@property (nonatomic, assign, readonly) NSInteger accountID;
@property (nonatomic, copy, readonly) NSString *secretKey;
@property (nonatomic, copy, readonly) NSString *aesSecretKey;

@property (nonatomic, assign, readonly) BOOL hasValidAccount;

+ (instancetype)shared;

@end

