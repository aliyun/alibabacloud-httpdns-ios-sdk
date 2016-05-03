//
//  HttpdnsReport.h
//  AlicloudHttpDNS
//
//  Created by ryan on 29/4/2016.
//  Copyright © 2016 alibaba-inc.com. All rights reserved.
//

#ifndef HttpdnsReport_h
#define HttpdnsReport_h

@interface HttpdnsReport : NSObject

+ (void)statAsync;
+ (BOOL)isDeviceReported;

@end

#endif /* HttpdnsReport_h */
