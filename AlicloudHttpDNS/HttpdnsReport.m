//
//  HttpdnsReport.m
//  AlicloudHttpDNS
//
//  Created by ryan on 29/4/2016.
//  Copyright © 2016 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpdnsReport.h"
#import "UTDID/UTDevice.h"
#import <CommonCrypto/CommonDigest.h>
#import "HttpdnsLog.h"

static BOOL reported = false;
const NSString *ak = @"23356390";
const NSString *sk = @"16594f72217bece5a457b4803a48f2da";
const NSString *manUrl = @"http://adash.man.aliyuncs.com:80/man/api";
const NSString *type = @"Raw";
const NSString *tag = @"HTTPDNS";

@implementation HttpdnsReport

+ (void)statAsync {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *utdid = [UTDevice utdid];
        HttpdnsLogDebug(@"stat: %@", utdid);
        NSString *contentBody = [NSString stringWithFormat:@"%@-%@", tag, utdid];
        NSString *content = [NSString stringWithFormat:@"%@%@%@", ak, type, [self md5:contentBody]];
        NSString *signContent = [NSString stringWithFormat:@"%@%@%@", sk, [self md5:content], sk];
        NSString *sign = [self sha1:signContent];
        NSString *queryURL = [NSString stringWithFormat:@"%@?ak=%@&s=%@", manUrl, ak, sign];
        
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:queryURL]];
        [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
        [request setHTTPShouldHandleCookies:NO];
        [request setTimeoutInterval:20];
        [request setHTTPMethod:@"POST"];
        NSString *boundary = [NSString stringWithFormat:@"===%@===", [NSDate date]];;
        // set Content-Type in HTTP header
        NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
        [request setValue:contentType forHTTPHeaderField: @"Content-Type"];
        // post body
        NSMutableData *body = [NSMutableData data];
        // add params (all params are strings)
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n", type] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Type: text/plain; charset=UTF-8\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@\r\n", contentBody] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        // setting the body of the post to the reqeust
        [request setHTTPBody:body];
        // set the content-length
        NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[body length]];
        [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
        NSError *error;
        NSURLResponse *response;
        NSData *result = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        if (error) {
            HttpdnsLogDebug(@"MAN API error: %@", error);
            return;
        } else {
            HttpdnsLogDebug(@"MAN stat: %@", [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding]);
            if(result.length > 0)
            {
                NSError *jsonError;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:result options:kNilOptions error:&jsonError];
                if (jsonError) {
                    HttpdnsLogDebug(@"MAN API json error: %@", jsonError);
                    return;
                }
                NSString *success = [json objectForKey:@"success"];
                if ([success isEqualToString:@"success"]) {
                    reported = true;
                    HttpdnsLogDebug(@"%@", @"stat success");
                } else {
                    HttpdnsLogDebug(@"stat error: %@", [json objectForKey:@"ret"]);
                }
            } else {
                HttpdnsLogDebug(@"%@", @"no response with MAN API.");
            }
        }
    });
}
+ (BOOL)isDeviceReported {
    return reported;
}

+ (NSString*)sha1:(NSString*)input
{
    
    NSData *data = [input dataUsingEncoding: NSUTF8StringEncoding];
    
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    
    NSMutableString* output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    
    for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    
    return output;
    
}

+ (NSString *)md5:(NSString *) input
{
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (CC_LONG)strlen(cStr), digest ); // This is the md5 call
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    
    return  output;
    
}

@end