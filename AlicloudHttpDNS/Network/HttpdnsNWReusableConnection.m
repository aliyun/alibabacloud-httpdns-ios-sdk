#import "HttpdnsNWReusableConnection.h"
#import "HttpdnsNWHTTPClient_Internal.h"

#import <Network/Network.h>
#import <Security/SecCertificate.h>
#import <Security/SecPolicy.h>
#import <Security/SecTrust.h>

#import "HttpdnsInternalConstant.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsPublicConstant.h"
#import "HttpdnsUtil.h"

@class HttpdnsNWHTTPClient;

// 只在此实现文件内可见的交换对象，承载一次请求/响应数据与状态
@interface HttpdnsNWHTTPExchange : NSObject

@property (nonatomic, strong, readonly) NSMutableData *buffer;
@property (nonatomic, strong, readonly) dispatch_semaphore_t semaphore;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL remoteClosed;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) NSUInteger headerEndIndex;
@property (nonatomic, assign) BOOL headerParsed;
@property (nonatomic, assign) BOOL chunked;
@property (nonatomic, assign) long long contentLength;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) dispatch_block_t timeoutBlock;

- (instancetype)init;

@end

@implementation HttpdnsNWHTTPExchange

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = [NSMutableData data];
        _semaphore = dispatch_semaphore_create(0);
        _headerEndIndex = NSNotFound;
        _contentLength = -1;
    }
    return self;
}

@end

@interface HttpdnsNWReusableConnection ()

@property (nonatomic, weak, readonly) HttpdnsNWHTTPClient *client;
@property (nonatomic, copy, readonly) NSString *host;
@property (nonatomic, copy, readonly) NSString *port;
@property (nonatomic, assign, readonly) BOOL useTLS;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

#if OS_OBJECT_USE_OBJC
@property (nonatomic, strong) nw_connection_t connectionHandle;
#else
@property (nonatomic, assign) nw_connection_t connectionHandle;
#endif
@property (nonatomic, strong) dispatch_semaphore_t stateSemaphore;
@property (nonatomic, assign) nw_connection_state_t state;
@property (nonatomic, strong) NSError *stateError;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, strong) HttpdnsNWHTTPExchange *currentExchange;
@property (nonatomic, assign, readwrite, getter=isInvalidated) BOOL invalidated;

@end

@implementation HttpdnsNWReusableConnection

- (void)dealloc {
    if (_connectionHandle) {
        nw_connection_set_state_changed_handler(_connectionHandle, NULL);
        nw_connection_cancel(_connectionHandle);
#if !OS_OBJECT_USE_OBJC
        nw_release(_connectionHandle);
#endif
        _connectionHandle = NULL;
    }
}

- (instancetype)initWithClient:(HttpdnsNWHTTPClient *)client
                          host:(NSString *)host
                          port:(NSString *)port
                        useTLS:(BOOL)useTLS {
    NSParameterAssert(client);
    NSParameterAssert(host);
    NSParameterAssert(port);

    self = [super init];
    if (!self) {
        return nil;
    }

    _client = client;
    _host = [host copy];
    _port = [port copy];
    _useTLS = useTLS;
    _queue = dispatch_queue_create("com.alibaba.sdk.httpdns.network.connection.reuse", DISPATCH_QUEUE_SERIAL);
    _stateSemaphore = dispatch_semaphore_create(0);
    _state = nw_connection_state_invalid;
    _lastUsedDate = [NSDate date];

    nw_endpoint_t endpoint = nw_endpoint_create_host(_host.UTF8String, _port.UTF8String);
    if (!endpoint) {
        return nil;
    }

    __weak typeof(self) weakSelf = self;
    nw_parameters_t parameters = NULL;
    if (useTLS) {
        parameters = nw_parameters_create_secure_tcp(^(nw_protocol_options_t tlsOptions) {
            if (!tlsOptions) {
                return;
            }
            sec_protocol_options_t secOptions = nw_tls_copy_sec_protocol_options(tlsOptions);
            if (!secOptions) {
                return;
            }
            if (![HttpdnsUtil isIPv4Address:host] && ![HttpdnsUtil isIPv6Address:host]) {
                sec_protocol_options_set_tls_server_name(secOptions, host.UTF8String);
            }
#if defined(__IPHONE_13_0) && (__IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0)
            if (@available(iOS 13.0, *)) {
                sec_protocol_options_add_tls_application_protocol(secOptions, "http/1.1");
            }
#endif
            __strong typeof(weakSelf) strongSelf = weakSelf;
            sec_protocol_options_set_verify_block(secOptions, ^(sec_protocol_metadata_t metadata, sec_trust_t secTrust, sec_protocol_verify_complete_t complete) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                BOOL isValid = NO;
                if (secTrust && strongSelf) {
                    SecTrustRef trustRef = sec_trust_copy_ref(secTrust);
                    if (trustRef) {
                        NSString *validIP = ALICLOUD_HTTPDNS_VALID_SERVER_CERTIFICATE_IP;
                        isValid = [strongSelf.client evaluateServerTrust:trustRef forDomain:validIP];
                        if (!isValid && [HttpdnsUtil isNotEmptyString:strongSelf.host]) {
                            isValid = [strongSelf.client evaluateServerTrust:trustRef forDomain:strongSelf.host];
                        }
                        if (!isValid && !strongSelf.stateError) {
                            strongSelf.stateError = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                                        code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                                                    userInfo:@{NSLocalizedDescriptionKey: @"TLS trust validation failed"}];
                        }
                        CFRelease(trustRef);
                    }
                }
                complete(isValid);
            }, strongSelf.queue);
        }, ^(nw_protocol_options_t tcpOptions) {
            nw_tcp_options_set_no_delay(tcpOptions, true);
        });
    } else {
        parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, ^(nw_protocol_options_t tcpOptions) {
            nw_tcp_options_set_no_delay(tcpOptions, true);
        });
    }

    if (!parameters) {
#if !OS_OBJECT_USE_OBJC
        nw_release(endpoint);
#endif
        return nil;
    }

    nw_connection_t connection = nw_connection_create(endpoint, parameters);

#if !OS_OBJECT_USE_OBJC
    nw_release(endpoint);
    nw_release(parameters);
#endif

    if (!connection) {
        return nil;
    }

    _connectionHandle = connection;

    nw_connection_set_queue(_connectionHandle, _queue);
    nw_connection_set_state_changed_handler(_connectionHandle, ^(nw_connection_state_t state, nw_error_t stateError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf handleStateChange:state error:stateError];
    });

    return self;
}

- (void)handleStateChange:(nw_connection_state_t)state error:(nw_error_t)error {
    _state = state;
    if (error) {
        _stateError = [HttpdnsNWHTTPClient errorFromNWError:error description:@"Connection state error"];
    }
    if (state == nw_connection_state_ready) {
        dispatch_semaphore_signal(_stateSemaphore);
        return;
    }
    if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
        self.invalidated = YES;
        if (!_stateError && error) {
            _stateError = [HttpdnsNWHTTPClient errorFromNWError:error description:@"Connection failed"];
        }
        dispatch_semaphore_signal(_stateSemaphore);
        HttpdnsNWHTTPExchange *exchange = self.currentExchange;
        if (exchange && !exchange.finished) {
            if (!exchange.error) {
                exchange.error = _stateError ?: [HttpdnsNWHTTPClient errorFromNWError:error description:@"Connection failed"];
            }
            exchange.finished = YES;
            dispatch_semaphore_signal(exchange.semaphore);
        }
    }
}

- (BOOL)openWithTimeout:(NSTimeInterval)timeout error:(NSError **)error {
    if (self.invalidated) {
        if (error) {
            *error = _stateError ?: [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                       code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Connection invalid"}];
        }
        return NO;
    }

    if (!_started) {
        _started = YES;
        nw_connection_start(_connectionHandle);
    }

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(_stateSemaphore, deadline);
    if (waitResult != 0) {
        self.invalidated = YES;
        if (error) {
            *error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                         code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                     userInfo:@{NSLocalizedDescriptionKey: @"Connection setup timed out"}];
        }
        nw_connection_cancel(_connectionHandle);
        return NO;
    }

    if (_state == nw_connection_state_ready) {
        return YES;
    }

    if (error) {
        *error = _stateError ?: [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                   code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                               userInfo:@{NSLocalizedDescriptionKey: @"Connection failed to become ready"}];
    }
    return NO;
}

- (BOOL)isViable {
    return !self.invalidated && _state == nw_connection_state_ready;
}

- (void)invalidate {
    if (self.invalidated) {
        return;
    }
    self.invalidated = YES;
    if (_connectionHandle) {
        nw_connection_cancel(_connectionHandle);
    }
}

- (nullable NSData *)sendRequestData:(NSData *)requestData
                             timeout:(NSTimeInterval)timeout
              remoteConnectionClosed:(BOOL *)remoteConnectionClosed
                               error:(NSError **)error {
    if (!requestData || requestData.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                         code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty HTTP request"}];
        }
        return nil;
    }

    if (![self isViable] || self.currentExchange) {
        if (error) {
            *error = _stateError ?: [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                       code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Connection not ready"}];
        }
        return nil;
    }

    HttpdnsNWHTTPExchange *exchange = [HttpdnsNWHTTPExchange new];
    __weak typeof(self) weakSelf = self;

    dispatch_sync(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            exchange.error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                 code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                             userInfo:@{NSLocalizedDescriptionKey: @"Connection released unexpectedly"}];
            exchange.finished = YES;
            dispatch_semaphore_signal(exchange.semaphore);
            return;
        }
        if (strongSelf.invalidated || strongSelf.currentExchange) {
            exchange.error = strongSelf.stateError ?: [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                                          code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                                                      userInfo:@{NSLocalizedDescriptionKey: @"Connection is busy"}];
            exchange.finished = YES;
            dispatch_semaphore_signal(exchange.semaphore);
            return;
        }
        strongSelf.currentExchange = exchange;
        dispatch_data_t payload = dispatch_data_create(requestData.bytes, requestData.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        dispatch_block_t timeoutBlock = dispatch_block_create(0, ^{
            if (exchange.finished) {
                return;
            }
            exchange.error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                 code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                             userInfo:@{NSLocalizedDescriptionKey: @"Request timed out"}];
            exchange.finished = YES;
            dispatch_semaphore_signal(exchange.semaphore);
            nw_connection_cancel(strongSelf.connectionHandle);
        });
        exchange.timeoutBlock = timeoutBlock;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), strongSelf.queue, timeoutBlock);

        nw_connection_send(strongSelf.connectionHandle, payload, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t sendError) {
            __strong typeof(strongSelf) innerSelf = strongSelf;
            if (!innerSelf) {
                return;
            }
            if (sendError) {
                dispatch_async(innerSelf.queue, ^{
                    if (!exchange.finished) {
                        exchange.error = [HttpdnsNWHTTPClient errorFromNWError:sendError description:@"Send failed"];
                        exchange.finished = YES;
                        dispatch_semaphore_signal(exchange.semaphore);
                        nw_connection_cancel(innerSelf.connectionHandle);
                    }
                });
                return;
            }
            [innerSelf startReceiveLoopForExchange:exchange];
        });
    });

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(exchange.semaphore, deadline);

    dispatch_sync(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (exchange.timeoutBlock) {
            dispatch_block_cancel(exchange.timeoutBlock);
            exchange.timeoutBlock = nil;
        }
        if (strongSelf && strongSelf.currentExchange == exchange) {
            strongSelf.currentExchange = nil;
        }
    });

    if (waitResult != 0) {
        if (!exchange.error) {
            exchange.error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                            userInfo:@{NSLocalizedDescriptionKey: @"Request wait timed out"}];
        }
        [self invalidate];
        if (error) {
            *error = exchange.error;
        }
        return nil;
    }

    if (exchange.error) {
        [self invalidate];
        if (error) {
            *error = exchange.error;
        }
        return nil;
    }

    if (remoteConnectionClosed) {
        *remoteConnectionClosed = exchange.remoteClosed;
    }

    return [exchange.buffer copy];
}

- (void)startReceiveLoopForExchange:(HttpdnsNWHTTPExchange *)exchange {
    __weak typeof(self) weakSelf = self;
    __block void (^receiveBlock)(dispatch_data_t, nw_content_context_t, bool, nw_error_t);
    __block __weak void (^weakReceiveBlock)(dispatch_data_t, nw_content_context_t, bool, nw_error_t);

    receiveBlock = ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t receiveError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (exchange.finished) {
            return;
        }
        if (receiveError) {
            exchange.error = [HttpdnsNWHTTPClient errorFromNWError:receiveError description:@"Receive failed"];
            exchange.finished = YES;
            dispatch_semaphore_signal(exchange.semaphore);
            return;
        }
        if (content) {
            dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                if (buffer && size > 0) {
                    [exchange.buffer appendBytes:buffer length:size];
                }
                return true;
            });
        }
        [strongSelf evaluateExchangeCompletion:exchange isRemoteComplete:is_complete];
        if (exchange.finished) {
            dispatch_semaphore_signal(exchange.semaphore);
            return;
        }
        if (is_complete) {
            exchange.remoteClosed = YES;
            if (!exchange.finished) {
                exchange.error = [NSError errorWithDomain:ALICLOUD_HTTPDNS_ERROR_DOMAIN
                                                     code:ALICLOUD_HTTPDNS_HTTPS_COMMON_ERROR_CODE
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Connection closed before response completed"}];
                exchange.finished = YES;
                dispatch_semaphore_signal(exchange.semaphore);
            }
            return;
        }
        void (^callback)(dispatch_data_t, nw_content_context_t, bool, nw_error_t) = weakReceiveBlock;
        if (callback && !exchange.finished) {
            nw_connection_receive(strongSelf.connectionHandle, 1, UINT32_MAX, callback);
        }
    };

    weakReceiveBlock = receiveBlock;
    nw_connection_receive(_connectionHandle, 1, UINT32_MAX, receiveBlock);
}

- (void)evaluateExchangeCompletion:(HttpdnsNWHTTPExchange *)exchange isRemoteComplete:(bool)isComplete {
    if (exchange.finished) {
        return;
    }

    if (isComplete) {
        // 远端已经发送完并关闭，需要提前标记，避免提前返回时漏记连接状态
        exchange.remoteClosed = YES;
    }

    if (!exchange.headerParsed) {
        NSUInteger headerEnd = NSNotFound;
        NSInteger statusCode = 0;
        NSDictionary<NSString *, NSString *> *headers = nil;
        NSError *headerError = nil;
        HttpdnsHTTPHeaderParseResult headerResult = [self.client tryParseHTTPHeadersInData:exchange.buffer
                                                                           headerEndIndex:&headerEnd
                                                                               statusCode:&statusCode
                                                                                  headers:&headers
                                                                                    error:&headerError];
        if (headerResult == HttpdnsHTTPHeaderParseResultError) {
            exchange.error = headerError;
            exchange.finished = YES;
            return;
        }
        if (headerResult == HttpdnsHTTPHeaderParseResultIncomplete) {
            return;
        }
        exchange.headerParsed = YES;
        exchange.headerEndIndex = headerEnd;
        exchange.statusCode = statusCode;
        NSString *contentLengthValue = headers[@"content-length"];
        if ([HttpdnsUtil isNotEmptyString:contentLengthValue]) {
            exchange.contentLength = [contentLengthValue longLongValue];
        }
        NSString *transferEncodingValue = headers[@"transfer-encoding"];
        if ([HttpdnsUtil isNotEmptyString:transferEncodingValue] && [transferEncodingValue rangeOfString:@"chunked" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            exchange.chunked = YES;
        }
    }

    if (!exchange.headerParsed) {
        return;
    }

    NSUInteger bodyOffset = exchange.headerEndIndex == NSNotFound ? 0 : exchange.headerEndIndex + 4;
    NSUInteger currentBodyLength = exchange.buffer.length > bodyOffset ? exchange.buffer.length - bodyOffset : 0;

    if (exchange.chunked) {
        NSError *chunkError = nil;
        HttpdnsHTTPChunkParseResult chunkResult = [self.client checkChunkedBodyCompletionInData:exchange.buffer
                                                                                headerEndIndex:exchange.headerEndIndex
                                                                                        error:&chunkError];
        if (chunkResult == HttpdnsHTTPChunkParseResultError) {
            exchange.error = chunkError;
            exchange.finished = YES;
            return;
        }
        if (chunkResult == HttpdnsHTTPChunkParseResultSuccess) {
            exchange.finished = YES;
            return;
        }
        return;
    }

    if (exchange.contentLength >= 0) {
        if ((long long)currentBodyLength >= exchange.contentLength) {
            exchange.finished = YES;
        }
        return;
    }

    if (isComplete) {
        exchange.remoteClosed = YES;
        exchange.finished = YES;
    }
}

@end

#if DEBUG
// 测试专用：连接状态操作实现
@implementation HttpdnsNWReusableConnection (DebugInspection)

- (void)debugSetLastUsedDate:(nullable NSDate *)date {
    self.lastUsedDate = date;
}

- (void)debugSetInUse:(BOOL)inUse {
    self.inUse = inUse;
}

- (void)debugInvalidate {
    [self invalidate];
}

@end
#endif

