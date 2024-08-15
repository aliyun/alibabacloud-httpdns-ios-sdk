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

#import <Foundation/Foundation.h>
#import "HttpdnsRequest.h"
#import "HttpdnsResult.h"
#import "HttpdnsDegradationDelegate.h"
#import "HttpdnsLoggerDelegate.h"

#define ALICLOUD_HTTPDNS_DEPRECATED(explain) __attribute__((deprecated(explain)))

extern NSString *const ALICLOUDHDNS_IPV4;
extern NSString *const ALICLOUDHDNS_IPV6;


@protocol HttpdnsTTLDelegate <NSObject>


/// 自定义HOST的TTL时长
/// @return 返回需要自定义的TTL时长
/// @param host 域名
/// @param ipType 当前查询的IP类型
/// @param ttl 当次域名解析返回的TTL
- (int64_t)httpdnsHost:(NSString *)host ipType:(AlicloudHttpDNS_IPType)ipType ttl:(int64_t)ttl;

@end

@interface HttpDnsService: NSObject

@property (nonatomic, assign, readonly) int accountID;

@property (nonatomic, copy, readonly) NSString *secretKey;

@property (nonatomic, weak, setter=setDelegateForDegradationFilter:) id<HttpDNSDegradationDelegate> delegate ALICLOUD_HTTPDNS_DEPRECATED("不再建议通过设置此回调实现降级逻辑，而是自行在调用HTTPDNS解析域名前做判断");

@property (nonatomic, weak) id<HttpdnsTTLDelegate> ttlDelegate;

@property (nonatomic, assign) NSTimeInterval timeoutInterval;

+ (instancetype)sharedInstance;

- (instancetype)autoInit;

- (instancetype)initWithAccountID:(int)accountID;

/*!
 * @brief 启用鉴权功能的初始化接口
 * @details 初始化、开启鉴权功能，并设置 HTTPDNS 服务 Account ID，鉴权功能对应的 secretKey。
 *          您可以从控制台获取您的 Account ID 、secretKey 信息。
 *          此方法会初始化为单例。
 * @param accountID 您的 HTTPDNS Account ID
 * @param secretKey 鉴权对应的 secretKey
 */
- (instancetype)initWithAccountID:(int)accountID secretKey:(NSString *)secretKey;


/// 开启鉴权功能后，鉴权的签名计算默认读取设备当前时间。若担心设备时间不准确导致签名不准确，可以使用此接口校正 APP 内鉴权计算使用的时间值
/// 注意，校正操作在 APP 的一个生命周期内生效，APP 重启后需要重新设置才能重新生效
/// @param currentTime 用于校正的时间戳，单位为秒
- (void)setAuthCurrentTime:(NSUInteger)authCurrentTime ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService setInternalAuthTimeBaseBySpecifyingCurrentTime:] instead.");


/// 开启鉴权功能后，鉴权的签名计算默认读取设备当前时间。若担心设备时间不准确导致签名不准确，可以使用此接口校正 APP 内鉴权计算使用的时间值
/// 注意，校正操作在 APP 的一个生命周期内生效，APP 重启后需要重新设置才能重新生效
/// @param currentTime 用于校正的时间戳，单位为秒
- (void)setInternalAuthTimeBaseBySpecifyingCurrentTime:(NSTimeInterval)currentTime;


/// 设置持久化缓存功能
/// @param enable YES: 开启 NO: 关闭
- (void)setCachedIPEnabled:(BOOL)enable ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService setPersistentCacheIPEnabled:] instead.");


/// 设置持久化缓存功能
/// 开启后，每次解析会将结果持久化缓存到本地，当下次应用启动时，可以从本地加载缓存解析结果，提高应用启动时获取解析结果的速度
/// @param enable YES: 开启 NO: 关闭
- (void)setPersistentCacheIPEnabled:(BOOL)enable;


/// 是否允许 HTTPDNS 返回 TTL 过期域名的 ip ，建议允许（默认不允许）
/// @param enable YES: 开启 NO: 关闭
- (void)setExpiredIPEnabled:(BOOL)enable ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService setReuseExpiredIPEnabled:] instead.");


/// 是否允许 HTTPDNS 返回 TTL 过期域名的 ip ，建议允许（默认不允许）
/// @param enable YES: 开启 NO: 关闭
- (void)setReuseExpiredIPEnabled:(BOOL)enable;


/// 设置 HTTPDNS 域名解析请求类型 ( HTTP / HTTPS )
/// 若不调用该接口，默认为 HTTP 请求。
/// HTTP 请求基于底层 CFNetwork 实现，不受 ATS 限制；
/// @param enable YES: HTTPS请求 NO: HTTP请求
- (void)setHTTPSRequestEnabled:(BOOL)enable;


/// 设置底层HTTPDNS网络请求超时时间，单位为秒
/// @param timeoutInterval 超时时间，单位为秒
- (void)setNetworkingTimeoutInterval:(NSTimeInterval)timeoutInterval;


/// 指定region，指定后会读取该region对应配置作为初始化配置
/// @param region 需要指定的region，缺省为中国大陆
- (void)setRegion:(NSString *)region;


/// 域名预解析 (ipv4)
/// 选择性的预先向 HTTPDNS SDK 中注册您后续可能会使用到的域名，以便 SDK 提前解析，减少后续解析域名时请求的时延
/// @param hosts 预解析列表数组
- (void)setPreResolveHosts:(NSArray *)hosts;


/// 域名预解析
/// @param hosts 域名
/// @param ipType 4: ipv4; 6: ipv6; 64: ipv4+ipv6
- (void)setPreResolveHosts:(NSArray *)hosts queryIPType:(AlicloudHttpDNS_IPType)ipType;


/// 本地日志 log 开关
/// @param enable YES: 打开 NO: 关闭
- (void)setLogEnabled:(BOOL)enable;


/// 设置网络切换时是否自动跟新所有域名解析结果
/// 如果打开此开关，在网络切换时，会自动刷新所有域名的解析结果，但会产生一定流量消耗
/// @param enable YES: 开启 NO: 关闭
- (void)setPreResolveAfterNetworkChanged:(BOOL)enable;


/// 设置IP俳优规则
/// @param IPRankingDatasource 设置对应域名的端口号
/// @{host: port}
- (void)setIPRankingDatasource:(NSDictionary<NSString *, NSNumber *> *)IPRankingDatasource;


/// 设置是否 开启 IPv6 结果解析。只有开启状态下，对域名的解析才会尝试解析v6记录并返回v6的结果
/// @param enable YES: 开启 NO: 关闭
- (void)enableIPv6:(BOOL)enable ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService setIPv6Enabled:] instead.");


/// 设置是否 开启 IPv6 结果解析。只有开启状态下，对域名的解析才会尝试解析v6记录并返回v6的结果
/// @param enable YES: 开启 NO: 关闭
- (void)setIPv6Enabled:(BOOL)enable;


/// 是否允许通过 CNCopyCurrentNetworkInfo 获取wifi ssid bssid
/// @param enable YES: 开启 NO: 关闭 ，默认关闭
- (void)enableNetworkInfo:(BOOL)enable ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService setReadNetworkInfoEnabled:] instead.");


/// 是否允许通过 CNCopyCurrentNetworkInfo 获取wifi ssid bssid
/// @param enable YES: 开启 NO: 关闭 ，默认关闭
- (void)setReadNetworkInfoEnabled:(BOOL)enable;


/// 是否开启IP探测功能
/// @param enable YES: 开启 NO: 关闭 默认打开
- (void)enableCustomIPRank:(BOOL)enable ALICLOUD_HTTPDNS_DEPRECATED("Deprecated, will be removed in the future.");


/// 设置软件自定义解析全局默认参数，设置后，调用软件自定义解析时，每个请求默认都会带上这里配置的参数
/// @param params 全局默认参数
- (void)setSdnsGlobalParams:(NSDictionary<NSString *, NSString *> *)params;


/// 设置日志输出回调，以实现自定义日志输出方式
/// @param logHandler 日志输出回调实现实例
- (void)setLogHandler:(id<HttpdnsLoggerProtocol>)logHandler;


/// 获取用于用户追踪的 sessionId
/// sessionId为随机生成，长度为 12 位，App 生命周期内保持不变
/// 为了排查可能的解析问题，需要您将 sessionId 和解析出的 IP 一起记录在日志中
/// 请参考: 解析异常排查之 “会话追踪方案” https://help.aliyun.com/document_detail/100530.html
- (NSString *)getSessionId;

/// 同步解析域名，会阻塞当前线程，直到从缓存中获取到有效解析结果，或者从服务器拿到最新解析结果
/// 如果允许复用过期的解析结果且存在过期结果的情况下，会先返回这个结果，然后启动后台线程去更新解析结果
/// 为了防止在主线程中误用本接口导致APP卡顿，本接口会做检测，若发现调用线程是主线程，则自动降级到resolveHostSyncNonBlocking接口的实现逻辑。
/// @param host 需要解析的域名
/// @param queryIpType 可设置为自动选择，ipv4，ipv6. 设置为自动选择时，会自动根据当前所处网络环境选择解析ipv4或ipv6
/// @return 解析结果
- (nullable HttpdnsResult *)resolveHostSync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType;

/// 同步解析域名，会阻塞当前线程，直到从缓存中获取到有效解析结果，或者从服务器拿到最新解析结果
/// 如果允许复用过期的解析结果且存在过期结果的情况下，会先返回这个结果，然后启动后台线程去更新解析结果
/// 为了防止在主线程中误用本接口导致APP卡顿，本接口会做检测，若发现调用线程是主线程，则自动降级到resolveHostSyncNonBlocking接口的实现逻辑。
/// @param host 需要解析的域名
/// @param queryIpType 可设置为自动选择，ipv4，ipv6. 设置为自动选择时，会自动根据当前所处网络环境选择解析ipv4或ipv6
/// @param sdnsParams 如果域名配置了sdns自定义解析，通过此参数携带自定义参数
/// @param cacheKey sdns自定义解析缓存key
/// @return 解析结果
- (nullable HttpdnsResult *)resolveHostSync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *, NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey;

/// 同步解析域名，会阻塞当前线程，直到从缓存中获取到有效解析结果，或者从服务器拿到最新解析结果
/// 如果允许复用过期的解析结果且存在过期结果的情况下，会先返回这个结果，然后启动后台线程去更新解析结果
/// 为了防止在主线程中误用本接口导致APP卡顿，本接口会做检测，若发现调用线程是主线程，则自动降级到resolveHostSyncNonBlocking接口的实现逻辑。
/// @param request 请求参数对象
/// @return 解析结果
- (nullable HttpdnsResult *)resolveHostSync:(HttpdnsRequest *)request;

/// 异步解析域名，不会阻塞当前线程，会在从缓存中获取到有效结果，或从服务器拿到最新解析结果后，通过回调返回结果
/// 如果允许复用过期的解析结果且存在过期结果的情况下，会先在回调中返回这个结果，然后启动后台线程去更新解析结果
/// @param host 需要解析的域名
/// @param queryIpType 可设置为自动选择，ipv4，ipv6. 设置为自动选择时，会自动根据当前所处网络环境选择解析ipv4或ipv6
/// @handler 解析结果回调
- (void)resolveHostAsync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType completionHandler:(void (^)(HttpdnsResult * nullable))handler;

/// 异步解析域名，不会阻塞当前线程，会在从缓存中获取到有效结果，或从服务器拿到最新解析结果后，通过回调返回结果
/// 如果允许复用过期的解析结果且存在过期结果的情况下，会先在回调中返回这个结果，然后启动后台线程去更新解析结果
/// @param host 需要解析的域名
/// @param queryIpType 可设置为自动选择，ipv4，ipv6. 设置为自动选择时，会自动根据当前所处网络环境选择解析ipv4或ipv6
/// @param sdnsParams 如果域名配置了sdns自定义解析，通过此参数携带自定义参数
/// @param cacheKey sdns自定义解析缓存key
/// @handler 解析结果回调
- (void)resolveHostAsync:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *, NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey completionHandler:(void (^)(HttpdnsResult * nullable))handler;

/// 异步解析域名，不会阻塞当前线程，会在从缓存中获取到有效结果，或从服务器拿到最新解析结果后，通过回调返回结果
/// 如果允许复用过期的解析结果且存在过期结果的情况下，会先在回调中返回这个结果，然后启动后台线程去更新解析结果
/// @param request 请求参数对象
/// @handler 解析结果回调
- (void)resolveHostAsync:(HttpdnsRequest *)request completionHandler:(void (^)(HttpdnsResult * nullable))handler;

/// 伪异步解析域名，不会阻塞当前线程，首次解析结果可能为空
/// 先查询缓存，缓存中存在有效结果(未过期，或者过期但配置了可以复用过期解析结果)，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 需要解析的域名
/// @param queryIpType 可设置为自动选择，ipv4，ipv6. 设置为自动选择时，会自动根据当前所处网络环境选择解析ipv4或ipv6
/// @return 解析结果
- (nullable HttpdnsResult *)resolveHostSyncNonBlocking:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType;

/// 伪异步解析域名，不会阻塞当前线程，首次解析结果可能为空
/// 先查询缓存，缓存中存在有效结果(未过期，或者过期但配置了可以复用过期解析结果)，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 需要解析的域名
/// @param queryIpType 可设置为自动选择，ipv4，ipv6. 设置为自动选择时，会自动根据当前所处网络环境选择解析ipv4或ipv6
/// @param sdnsParam 如果域名配置了sdns自定义解析，通过此参数携带自定义参数
/// @param cacheKey sdns自定义解析缓存key
/// @return 解析结果
- (nullable HttpdnsResult *)resolveHostSyncNonBlocking:(NSString *)host byIpType:(HttpdnsQueryIPType)queryIpType withSdnsParams:(NSDictionary<NSString *, NSString *> *)sdnsParams sdnsCacheKey:(NSString *)cacheKey;

/// 伪异步解析域名，不会阻塞当前线程，首次解析结果可能为空
/// 先查询缓存，缓存中存在有效结果(未过期，或者过期但配置了可以复用过期解析结果)，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param request 请求参数对象
/// @return 解析结果
- (nullable HttpdnsResult *)resolveHostSyncNonBlocking:(HttpdnsRequest *)request;


/// 获取域名对应的IP，单IP
/// @param host 域名
- (NSString *)getIpByHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 异步接口，首次结果可能为空，获取域名对应的IP数组，多IP
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
- (NSArray *)getIpsByHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 异步接口，首次结果可能为空，获取域名对应的ipv6, 单IP （需要开启ipv6 开关 enableIPv6）
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
- (NSString *)getIPv6ByHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 异步接口，首次结果可能为空，获取域名对应的ipv6数组, 多IP （需要开启ipv6 开关 enableIPv6）
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
- (NSArray *)getIPv6sByHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 同时获取ipv4 ipv6的IP （需要开启ipv6 开关 enableIPv6）
/// @param host 域名
/// @result 返回字典类型结构
///   {
///         ALICLOUDHDNS_IPV4: ['xxx.xxx.xxx.xxx', 'xxx.xxx.xxx.xxx'],
///         ALICLOUDHDNS_IPV6: ['xx:xx:xx:xx:xx:xx:xx:xx', 'xx:xx:xx:xx:xx:xx:xx:xx']
///   }
- (NSDictionary <NSString *, NSArray *>*)getIPv4_v6ByHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 根据当前设备的网络状态自动返回域名对应的 IPv4/IPv6地址组
/// 使用此API 需要确保 enableIPv6 开关已打开
///   设备网络            返回域名IP
///   IPv4 Only           IPv4
///   IPv6 Only           IPv6 （如果没有Pv6返回空）
///   双栈                 IPv4/IPV6
/// @param host 要解析的域名
/// @result 返回字典类型结构
///   {
///         ALICLOUDHDNS_IPV4: ['xxx.xxx.xxx.xxx', 'xxx.xxx.xxx.xxx'],
///         ALICLOUDHDNS_IPV6: ['xx:xx:xx:xx:xx:xx:xx:xx', 'xx:xx:xx:xx:xx:xx:xx:xx']
///   }
-(NSDictionary <NSString *, NSArray *>*)autoGetIpsByHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 异步接口，首次结果可能为空，获取域名对应的IPv4地址，单IPv4
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
- (NSString *)getIPv4ForHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 异步接口，首次结果可能为空，获取域名对应的IP数组，多IP
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
- (NSArray *)getIPv4ListForHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 获取IPv4地址列表，同步接口，必须在子线程中执行，否则会转变为异步接口
/// 同步接口有超时机制，超时时间为[HttpDnsService sharedInstance].timeoutInterval, 但是超时上限为5s，
/// 即使[HttpDnsService sharedInstance].timeoutInterval设置的时间大于5s，同步接口也最多阻塞当前线程5s
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起同步解析请求
/// @param host 域名
- (NSArray *)getIPv4ListForHostSync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSync:byIpType:] instead.");

/// 异步接口，首次结果可能为空，获取域名对应的ipv6, 单IP （需要开启ipv6 开关 enableIPv6）
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
- (NSString *)getIPv6ForHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 异步接口，首次结果可能为空，获取域名对应的ipv6数组, 多IP （需要开启ipv6 开关 enableIPv6）
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
- (NSArray *)getIPv6ListForHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 获取IPv6地址列表，同步接口，必须在子线程中执行，否则会转变为异步接口
/// 同步接口有超时机制，超时时间为[HttpDnsService sharedInstance].timeoutInterval, 但是超时上限为5s，
/// 即使[HttpDnsService sharedInstance].timeoutInterval设置的时间大于5s，同步接口也最多阻塞当前线程5s
/// @param host 域名
- (NSArray *)getIPv6ListForHostSync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSync:byIpType:] instead.");

/// 异步接口，首次结果可能为空，获取域名对应格式化后的IP (针对ipv6)
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
- (NSString *)getIpByHostAsyncInURLFormat:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");


/// 异步接口，首次结果可能为空，同时获取ipv4 ipv6的IP （需要开启ipv6 开关 enableIPv6）
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
/// @result 返回字典类型结构
///   {
///         ALICLOUDHDNS_IPV4: ['xxx.xxx.xxx.xxx', 'xxx.xxx.xxx.xxx'],
///         ALICLOUDHDNS_IPV6: ['xx:xx:xx:xx:xx:xx:xx:xx', 'xx:xx:xx:xx:xx:xx:xx:xx']
///   }
- (NSDictionary <NSString *, NSArray *>*)getHttpDnsResultHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// NOTE: 同步接口，必须在子线程中执行，否则会转变为异步接口
/// 同步接口有超时机制，超时时间为[HttpDnsService sharedInstance].timeoutInterval, 但是超时上限为5s，
/// 即使[HttpDnsService sharedInstance].timeoutInterval设置的时间大于5s，同步接口也最多阻塞当前线程5s
/// 同时获取ipv4 + ipv6的IP （需要开启ipv6 开关 enableIPv6）
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
/// @result 返回字典类型结构
///   {
///         ALICLOUDHDNS_IPV4: ['xxx.xxx.xxx.xxx', 'xxx.xxx.xxx.xxx'],
///         ALICLOUDHDNS_IPV6: ['xx:xx:xx:xx:xx:xx:xx:xx', 'xx:xx:xx:xx:xx:xx:xx:xx']
///   }
- (NSDictionary <NSString *, NSArray *>*)getHttpDnsResultHostSync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSync:byIpType:] instead.");

/// 异步接口，首次结果可能为空，根据当前设备的网络状态自动返回域名对应的 IPv4/IPv6地址组
/// 使用此API 需要确保 enableIPv6 开关已打开
///   设备网络            返回域名IP
///   IPv4 Only           IPv4
///   IPv6 Only           IPv6 （如果没有Pv6返回空）
///   双栈                 IPv4/IPV6
/// @param host 要解析的域名
/// @result 返回字典类型结构
///   {
///         ALICLOUDHDNS_IPV4: ['xxx.xxx.xxx.xxx', 'xxx.xxx.xxx.xxx'],
///         ALICLOUDHDNS_IPV6: ['xx:xx:xx:xx:xx:xx:xx:xx', 'xx:xx:xx:xx:xx:xx:xx:xx']
///   }
-(NSDictionary <NSString *, NSArray *>*)autoGetHttpDnsResultForHostAsync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:] instead.");

/// 根据当前设备的网络状态自动返回域名对应的 IPv4/IPv6地址组，同步接口，必须在子线程中执行，否则会转变为异步接口
/// 同步接口有超时机制，超时时间为[HttpDnsService sharedInstance].timeoutInterval, 但是超时上限为5s，
/// 即使[HttpDnsService sharedInstance].timeoutInterval设置的时间大于5s，同步接口也最多阻塞当前线程5s
/// 根据当前网络栈自动获取ipv4 ipv6的IP （需要开启ipv6 开关 enableIPv6）
/// 先查询缓存，缓存中存在未过期的结果，则直接返回结果，如果缓存未命中，则发起异步解析请求
/// @param host 域名
/// @result 返回字典类型结构
///   {
///         ALICLOUDHDNS_IPV4: ['xxx.xxx.xxx.xxx', 'xxx.xxx.xxx.xxx'],
///         ALICLOUDHDNS_IPV6: ['xx:xx:xx:xx:xx:xx:xx:xx', 'xx:xx:xx:xx:xx:xx:xx:xx']
///   }
- (NSDictionary <NSString *, NSArray *>*)autoGetHttpDnsResultForHostSync:(NSString *)host ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSync:byIpType:] instead.");

/// 软件自定义解析接口
- (NSDictionary *)getIpsByHostAsync:(NSString *)host withParams:(NSDictionary<NSString *, NSString *> *)params withCacheKey:(NSString *)cacheKey ALICLOUD_HTTPDNS_DEPRECATED("Deprecated. Use -[HttpDnsService resolveHostSyncNonBlocking:byIpType:withSdnsParams:sdnsCacheKey:] instead.");


/// 清除指定host缓存（内存+沙盒数据库）
/// @param hostArray 需要清除的host域名数组。如果需要清空全部数据传nil或者空数组即可
- (void)cleanHostCache:(NSArray<NSString *> *)hostArray;

/// 清除当前所有host缓存 (内存+沙盒数据库)
- (void)cleanAllHostCache;

/// 清理已经配置的软件自定义解析全局参数
- (void)clearSdnsGlobalParams;

@end
