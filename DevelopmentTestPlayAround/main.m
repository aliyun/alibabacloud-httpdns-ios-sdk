//
//  main.m
//  DevelopmentTestPlayAround
//
//  Created by zhouzhuo on 5/2/15.
//  Copyright (c) 2015 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsRequest.h"

@interface ClassObject : NSObject

-(void)foo;

@end

@implementation ClassObject

-(void)foo {
    NSLog(@"%@", [NSThread currentThread]);
    dispatch_queue_t syncQueue = dispatch_queue_create("com", NULL);
    dispatch_async(syncQueue, ^{
        NSLog(@"%@", [NSThread currentThread]);
        NSLog(@"Hello world");
    });
    CFRunLoopStop(CFRunLoopGetCurrent());
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        ClassObject *object = [[ClassObject alloc] init];
        NSLog(@"start");
        NSLog(@"%@", [NSThread currentThread]);
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1 target:object selector:@selector(foo) userInfo:nil repeats:NO];
        [timer invalidate];
        NSLog(@"%d", (int)[timer isValid]);
        CFRunLoopRun();
        sleep(1);
        NSLog(@"%d", (int)[timer isValid]);
        [timer invalidate];
    }
    return 0;
}