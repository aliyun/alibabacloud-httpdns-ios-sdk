//
//  HttpdnsIPQualityDetector.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2025/3/13.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsIPQualityDetector.h"
#import "HttpdnsIpv6Adapter.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <unistd.h>
#import <sys/time.h>
#import <fcntl.h>
#import <errno.h>
#import "HttpdnsLog_Internal.h"

// 定义任务类，替代之前的结构体，确保正确的内存管理
@interface HttpdnsDetectionTask : NSObject
@property (nonatomic, copy) NSString *cacheKey;
@property (nonatomic, copy) NSString *ip;
@property (nonatomic, strong) NSNumber *port;
@property (nonatomic, copy) HttpdnsIPQualityCallback callback;
@end

@implementation HttpdnsDetectionTask
@end

@interface HttpdnsIPQualityDetector ()

@property (nonatomic, strong) dispatch_queue_t detectQueue;
@property (nonatomic, strong) dispatch_semaphore_t concurrencySemaphore;
@property (nonatomic, strong) NSMutableArray<HttpdnsDetectionTask *> *pendingTasks;
@property (nonatomic, strong) NSLock *pendingTasksLock;
@property (nonatomic, assign) BOOL isProcessingPendingTasks;

/**
 * 最大并发检测数量，默认为10
 */
@property (nonatomic, assign) NSUInteger maxConcurrentDetections;

@end

@implementation HttpdnsIPQualityDetector

+ (instancetype)sharedInstance {
    static HttpdnsIPQualityDetector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HttpdnsIPQualityDetector alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _detectQueue = dispatch_queue_create("com.aliyun.httpdns.ipqualitydetector", DISPATCH_QUEUE_CONCURRENT);
        _maxConcurrentDetections = 10;
        _concurrencySemaphore = dispatch_semaphore_create(_maxConcurrentDetections);
        _pendingTasks = [NSMutableArray array];
        _pendingTasksLock = [[NSLock alloc] init];
        _isProcessingPendingTasks = NO;
    }
    return self;
}

- (void)scheduleIPQualityDetection:(NSString *)cacheKey
                                ip:(NSString *)ip
                              port:(NSNumber *)port
                          callback:(HttpdnsIPQualityCallback)callback {
    if (!cacheKey || !ip || !callback) {
        HttpdnsLogDebug("IPQualityDetector invalid parameters for detection: cacheKey=%@, ip=%@", cacheKey, ip);
        return;
    }

    // 尝试获取信号量，如果获取不到，说明已达到最大并发数
    if (dispatch_semaphore_wait(_concurrencySemaphore, DISPATCH_TIME_NOW) != 0) {
        // 将任务加入等待队列
        HttpdnsLogDebug("IPQualityDetector reached max concurrent limit, queueing task for %@", ip);
        [self addPendingTask:cacheKey ip:ip port:port callback:callback];
        return;
    }

    // 获取到信号量，可以执行检测
    [self executeDetection:cacheKey ip:ip port:port callback:callback];
}

- (void)addPendingTask:(NSString *)cacheKey ip:(NSString *)ip port:(NSNumber *)port callback:(HttpdnsIPQualityCallback)callback {
    // 创建任务对象，ARC会自动管理内存
    HttpdnsDetectionTask *task = [[HttpdnsDetectionTask alloc] init];
    task.cacheKey = cacheKey;
    task.ip = ip;
    task.port = port;
    task.callback = callback;

    // 加锁添加任务
    [_pendingTasksLock lock];
    [_pendingTasks addObject:task];
    [_pendingTasksLock unlock];

    // 如果没有正在处理等待队列，则开始处理
    [self processPendingTasksIfNeeded];
}

- (NSUInteger)pendingTasksCount {
    [_pendingTasksLock lock];
    NSUInteger count = _pendingTasks.count;
    [_pendingTasksLock unlock];
    return count;
}

- (void)processPendingTasksIfNeeded {
    [_pendingTasksLock lock];
    BOOL shouldProcess = !_isProcessingPendingTasks && _pendingTasks.count > 0;
    if (shouldProcess) {
        _isProcessingPendingTasks = YES;
    }
    [_pendingTasksLock unlock];

    if (shouldProcess) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self processPendingTasks];
        });
    }
}

- (void)processPendingTasks {
    while (1) {
        // 尝试获取信号量
        if (dispatch_semaphore_wait(_concurrencySemaphore, DISPATCH_TIME_NOW) != 0) {
            // 无法获取信号量，等待一段时间后重试
            [NSThread sleepForTimeInterval:0.1];
            continue;
        }

        // 获取到信号量，取出一个等待任务
        HttpdnsDetectionTask *task = nil;

        [_pendingTasksLock lock];
        if (_pendingTasks.count > 0) {
            task = _pendingTasks.firstObject;
            [_pendingTasks removeObjectAtIndex:0];
        } else {
            // 没有等待任务了，结束处理
            _isProcessingPendingTasks = NO;
            [_pendingTasksLock unlock];
            // 释放多余的信号量
            dispatch_semaphore_signal(_concurrencySemaphore);
            break;
        }
        [_pendingTasksLock unlock];

        // 执行任务
        [self executeDetection:task.cacheKey ip:task.ip port:task.port callback:task.callback];
    }
}

- (void)executeDetection:(NSString *)cacheKey ip:(NSString *)ip port:(NSNumber *)port callback:(HttpdnsIPQualityCallback)callback {
    // 创建强引用以确保在异步操作期间对象不会被释放
    HttpdnsIPQualityCallback strongCallback = [callback copy];

    // 使用后台队列进行检测，避免阻塞主线程
    dispatch_async(self.detectQueue, ^{
        NSInteger costTime = [self tcpConnectToIP:ip port:port ? [port intValue] : 80];

        // 在后台线程回调结果
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            strongCallback(cacheKey, ip, costTime);

            // 释放信号量，允许执行下一个任务
            dispatch_semaphore_signal(self->_concurrencySemaphore);

            // 检查是否有等待的任务需要处理
            [self processPendingTasksIfNeeded];
        });
    });
}

- (NSInteger)tcpConnectToIP:(NSString *)ip port:(int)port {
    if (!ip || port <= 0) {
        return -1;
    }
    int socketFd;
    struct sockaddr_in serverAddr;
    struct sockaddr_in6 serverAddr6;
    void *serverAddrPtr;
    socklen_t serverAddrLen;
    BOOL isIPv6 = [HttpdnsIPv6Adapter isIPv6Address:ip];
    BOOL isIpv4 = [HttpdnsIPv6Adapter isIPv4Address:ip];

    // 创建socket
    if (isIPv6) {
        socketFd = socket(AF_INET6, SOCK_STREAM, 0);
        if (socketFd < 0) {
            HttpdnsLogDebug("IPQualityDetector failed to create IPv6 socket: %s", strerror(errno));
            return -1;
        }

        memset(&serverAddr6, 0, sizeof(serverAddr6));
        serverAddr6.sin6_family = AF_INET6;
        serverAddr6.sin6_port = htons(port);
        inet_pton(AF_INET6, [ip UTF8String], &serverAddr6.sin6_addr);

        serverAddrPtr = &serverAddr6;
        serverAddrLen = sizeof(serverAddr6);
    } else if (isIpv4) {
        socketFd = socket(AF_INET, SOCK_STREAM, 0);
        if (socketFd < 0) {
            HttpdnsLogDebug("IPQualityDetector failed to create IPv4 socket: %s", strerror(errno));
            return -1;
        }

        memset(&serverAddr, 0, sizeof(serverAddr));
        serverAddr.sin_family = AF_INET;
        serverAddr.sin_port = htons(port);
        inet_pton(AF_INET, [ip UTF8String], &serverAddr.sin_addr);

        serverAddrPtr = &serverAddr;
        serverAddrLen = sizeof(serverAddr);
    } else {
        return -1;
    }

    // 设置非阻塞模式
    int flags = fcntl(socketFd, F_GETFL, 0);
    fcntl(socketFd, F_SETFL, flags | O_NONBLOCK);

    // 开始计时
    struct timeval startTime, endTime;
    gettimeofday(&startTime, NULL);

    // 尝试连接
    int connectResult = connect(socketFd, serverAddrPtr, serverAddrLen);

    if (connectResult < 0) {
        if (errno == EINPROGRESS) {
            // 连接正在进行中，使用select等待
            fd_set fdSet;
            struct timeval timeout;

            FD_ZERO(&fdSet);
            FD_SET(socketFd, &fdSet);

            // 设置超时时间为2秒
            // 更长的超时时间不是很有必要，因为建连超过2秒的IP，已经没有优选必要了
            timeout.tv_sec = 2;
            timeout.tv_usec = 0;

            int selectResult = select(socketFd + 1, NULL, &fdSet, NULL, &timeout);

            if (selectResult <= 0) {
                // 超时或错误
                HttpdnsLogDebug("IPQualityDetector connection to %@ timed out or error: %s", ip, strerror(errno));
                close(socketFd);
                return -1;
            } else {
                // 检查连接是否成功
                int error;
                socklen_t errorLen = sizeof(error);
                if (getsockopt(socketFd, SOL_SOCKET, SO_ERROR, &error, &errorLen) < 0 || error != 0) {
                    HttpdnsLogDebug("IPQualityDetector connection to %@ failed after select: %s", ip, strerror(error));
                    close(socketFd);
                    return -1;
                }
            }
        } else {
            // 其他错误
            HttpdnsLogDebug("IPQualityDetector connection to %@ failed: %s", ip, strerror(errno));
            close(socketFd);
            return -1;
        }
    }

    // 结束计时
    gettimeofday(&endTime, NULL);

    // 关闭socket
    close(socketFd);

    // 计算耗时（毫秒）
    long seconds = endTime.tv_sec - startTime.tv_sec;
    long microseconds = endTime.tv_usec - startTime.tv_usec;
    NSInteger costTime = (seconds * 1000) + (microseconds / 1000);

    return costTime;
}

@end
