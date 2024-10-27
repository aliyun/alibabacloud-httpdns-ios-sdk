//
//  HttpdnsCFHttpWrapper.m
//  AlicloudHttpDNS
//
//  Created by xuyecan on 2024/10/22.
//  Copyright © 2024 alibaba-inc.com. All rights reserved.
//

#import "HttpdnsCFHttpWrapper.h"
#import "HttpdnsLog_Internal.h"
#import "HttpdnsService_Internal.h"
#import "HttpdnsUtil.h"
#import "HttpdnsConstants.h"
#import <CFNetwork/CFNetwork.h>

typedef struct {
    NSURL *url;
    CFReadStreamRef readStream;
    CFRunLoopTimerRef timer;
    BOOL hasTimedOut;
    NSMutableData *responseData;
    void (^completionHandler)(NSData *data, NSError *error);
} RequestContext;

@interface HttpdnsCFHttpWrapper ()

- (void)cancelRequest:(RequestContext *)context;
- (void)handleTimeout:(RequestContext *)context;
- (void)handleResponseForStream:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType context:(RequestContext *)context;

@end

@implementation HttpdnsCFHttpWrapper

- (void)sendHTTPRequestWithURL:(NSURL *)url
                    completion:(void (^)(NSData *data, NSError *error))completion {
    CFURLRef cfURL = (__bridge CFURLRef)url;
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(kCFAllocatorDefault, CFSTR("GET"), cfURL, kCFHTTPVersion1_1);

    CFStringRef headerFieldName = CFSTR("User-Agent");
    CFStringRef headerFieldValue = (__bridge CFStringRef)([HttpdnsUtil generateUserAgent]);
    CFHTTPMessageSetHeaderFieldValue(request, headerFieldName, headerFieldValue);

    CFReadStreamRef readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, request);

    RequestContext *context = malloc(sizeof(RequestContext));
    context->url = url;
    context->readStream = readStream;
    context->hasTimedOut = NO;
    context->responseData = [NSMutableData data];
    context->completionHandler = [completion copy];

    CFStreamClientContext clientContext = {0, context, NULL, NULL, NULL};
    CFReadStreamSetClient(readStream, kCFStreamEventHasBytesAvailable | kCFStreamEventEndEncountered | kCFStreamEventErrorOccurred,
                          (CFReadStreamClientCallBack)&HttpdnsHttpAgent_handleResponse, &clientContext);

    CFReadStreamScheduleWithRunLoop(readStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);

    // Create and schedule the timeout timer
    CFRunLoopTimerContext timerContext = {0, context, NULL, NULL, NULL};
    double timeoutInterval = [HttpDnsService sharedInstance].timeoutInterval;
    context->timer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + timeoutInterval, 0, 0, 0, &HttpdnsHttpAgent_handleTimeout, &timerContext);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), context->timer, kCFRunLoopCommonModes);

    if (CFReadStreamOpen(readStream)) {
        CFRunLoopRun();
    } else {
        HttpdnsLogDebug("Failed to open read stream for request %@", url);
        [self cancelRequest:context];
        completion(nil, [NSError errorWithDomain:@"HttpdnsCFHttpWrapperError" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to open read stream"}]);
    }

    CFRelease(request);
}

#pragma mark - Private Methods

- (void)cancelRequest:(RequestContext *)context {
    if (context->readStream) {
        CFReadStreamClose(context->readStream);
        CFReadStreamUnscheduleFromRunLoop(context->readStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
        CFRelease(context->readStream);
        context->readStream = NULL;
    }

    if (context->timer) {
        CFRunLoopTimerInvalidate(context->timer);
        CFRelease(context->timer);
        context->timer = NULL;
    }

    free(context);
}

- (void)handleTimeout:(RequestContext *)context {
    if (!context->hasTimedOut) {
        context->hasTimedOut = YES;
        HttpdnsLogDebug("Request timed out for request: %@", [context->url absoluteString]);

        if (context->completionHandler) {
            context->completionHandler(nil, [NSError errorWithDomain:@"HttpdnsHttpAgentError" code:ALICLOUD_HTTPDNS_HTTP_TIMEOUT_ERROR_CODE userInfo:@{NSLocalizedDescriptionKey: @"Request Timeout"}]);
            context->completionHandler = nil;
        }

        [self cancelRequest:context];
        CFRunLoopStop(CFRunLoopGetCurrent());
    }
}

- (void)handleResponseForStream:(CFReadStreamRef)stream
                      eventType:(CFStreamEventType)eventType
                        context:(RequestContext *)context {
    if (context->hasTimedOut) {
        return;
    }

    switch (eventType) {
        case kCFStreamEventHasBytesAvailable: {
            CFHTTPMessageRef responseMessage = (CFHTTPMessageRef)CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);
            if (responseMessage) {
                CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(responseMessage);
                if (statusCode == 200) {
                    UInt8 buffer[8 * 1024];
                    CFIndex bytesRead = CFReadStreamRead(stream, buffer, sizeof(buffer));
                    if (bytesRead > 0) {
                        [context->responseData appendBytes:buffer length:bytesRead];
                    }
                } else {
                    NSError *error = [NSError errorWithDomain:@"HttpdnsHttpClientWrapperError"
                                                         code:statusCode
                                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTPStatusError: %ld", (long)statusCode]}];
                    if (context->completionHandler) {
                        context->completionHandler(nil, error);
                        context->completionHandler = nil;
                    }
                    [self cancelRequest:context];
                    CFRunLoopStop(CFRunLoopGetCurrent());
                }

                CFRelease(responseMessage);
            }
            break;
        }
        case kCFStreamEventEndEncountered: {
            HttpdnsLogDebug("Request completed successfully for url: %@", [context->url absoluteString]);
            if (context->completionHandler) {
                context->completionHandler([context->responseData copy], nil);
                context->completionHandler = nil;
            }
            [self cancelRequest:context];
            CFRunLoopStop(CFRunLoopGetCurrent());
            break;
        }
        case kCFStreamEventErrorOccurred: {
            CFErrorRef error = CFReadStreamCopyError(stream);
            HttpdnsLogDebug("Request error occurred: %@, url: %@", error, [context->url absoluteString]);
            if (context->completionHandler) {
                NSError *nsError = (__bridge_transfer NSError *)error;
                context->completionHandler(nil, nsError);
                context->completionHandler = nil;
            }
            [self cancelRequest:context];
            CFRunLoopStop(CFRunLoopGetCurrent());
            break;
        }
        default:
            break;
    }
}

#pragma mark - C Callbacks

static void HttpdnsHttpAgent_handleTimeout(CFRunLoopTimerRef timer, void *info) {
    RequestContext *context = (RequestContext *)info;
    HttpdnsCFHttpWrapper *agent = [[HttpdnsCFHttpWrapper alloc] init];
    [agent handleTimeout:context];
}

static void HttpdnsHttpAgent_handleResponse(CFReadStreamRef stream, CFStreamEventType eventType, void *clientCallBackInfo) {
    RequestContext *context = (RequestContext *)clientCallBackInfo;
    HttpdnsCFHttpWrapper *agent = [[HttpdnsCFHttpWrapper alloc] init];
    [agent handleResponseForStream:stream eventType:eventType context:context];
}

@end
