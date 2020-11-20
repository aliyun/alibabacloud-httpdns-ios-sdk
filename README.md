# httpdns

请参考官网文档，了解httpdns功能。[https://help.aliyun.com/product/30100.html?spm=a2c4g.750001.list.154.2d0d7b13T0aYuX](https://help.aliyun.com/product/30100.html?spm=a2c4g.750001.list.154.2d0d7b13T0aYuX)

## 注意

请从控制台下载AliyunEmasServices-Info.plist，并替换掉AlicloudHttpDNSDemo下的同名文件，以确保帐户参数正确

请在HttpdnsRequestScheduler中配置你所使用账号的初始服务IP，否则无法请求
```objective-c
//HttpdnsRequestScheduler.m

// 此处需要配置自己的初始服务IP
NSString * ALICLOUD_HTTPDNS_SERVER_IP_ACTIVATED = @"初始服务IP";
```


请在HttpdnsConstants中配置你所使用账号的调度服务IP，否则无法请求
```objective-c
//HttpdnsConstants.h

// 此处需要配置自己的初始服务IP
static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP = @"调度服务IP";

static NSString *const ALICLOUD_HTTPDNS_SCHEDULE_CENTER_REQUEST_HOST_IP_2 = @"调度服务IP";
```


