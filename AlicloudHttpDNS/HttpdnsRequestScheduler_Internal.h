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

#import "HttpdnsRequestScheduler.h"

@interface HttpdnsRequestTestHelper : NSObject

- (void)setFirstIPWrongForTest;

- (void)shortResetActivatedIPTimeForTest;
- (void)setTwoFirstIPWrongForTest;
- (void)setFourFirstIPWrongForTest;
- (void)zeroSnifferTimeForTest;

@end

@interface HttpdnsRequestScheduler ()

@property (nonatomic, assign) NSInteger activatedServerIPIndex;

- (void)setServerDisable:(BOOL)serverDisable host:(NSString *)host;

- (void)setServerDisable:(BOOL)serverDisable host:(NSString *)host activatedServerIPIndex:(NSInteger)activatedServerIPIndex;

- (BOOL)isServerDisable;

@property (nonatomic, strong) HttpdnsRequestTestHelper *testHelper;

+ (void)configureServerIPsAndResetActivatedIPTime;

@end

