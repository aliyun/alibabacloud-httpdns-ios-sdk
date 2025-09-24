# Alicloud HTTPDNS iOS SDK

面向 iOS 的 HTTP/HTTPS DNS 解析 SDK，提供鉴权与可选 AES 加密、IPv4/IPv6 双栈解析、缓存与调度、预解析等能力。最低支持 iOS 10.0。

## 功能特性
- 鉴权请求与可选 AES 传输加密
- IPv4/IPv6 双栈解析，支持自动/同时解析
- 内存 + 持久化缓存与 TTL 控制，可选择复用过期 IP
- 预解析、区域路由、网络切换自动刷新
- 可定制日志回调与会话追踪 `sessionId`

## 安装（CocoaPods）
在 `Podfile` 中添加：

```ruby
platform :ios, '10.0'
target 'YourApp' do
  pod 'AlicloudHTTPDNS', '~> 3.2.1'
end
```

执行 `pod install` 安装依赖。

## 快速开始
Objective‑C
```objc
#import <AlicloudHttpDNS/AlicloudHttpDNS.h>

// 使用鉴权初始化（单例）；密钥请勿硬编码到仓库
HttpDnsService *service = [[HttpDnsService alloc] initWithAccountID:1000000
                                                         secretKey:@"<YOUR_SECRET>"];
[service setPersistentCacheIPEnabled:YES];
[service setPreResolveHosts:@[@"www.aliyun.com"] byIPType:HttpdnsQueryIPTypeAuto];

// 同步解析（会根据网络自动选择 v4/v6）
HttpdnsResult *r = [service resolveHostSync:@"www.aliyun.com" byIpType:HttpdnsQueryIPTypeAuto];
NSLog(@"IPv4: %@", r.ips);
```

Swift
```swift
import AlicloudHttpDNS

_ = HttpDnsService(accountID: 1000000, secretKey: "<YOUR_SECRET>")
let svc = HttpDnsService.sharedInstance()
let res = svc?.resolveHostSync("www.aliyun.com", byIpType: .auto)
print(res?.ips ?? [])
```

提示
- 启动时通过 `setPreResolveHosts(_:byIPType:)` 预热热点域名。
- 如需在刷新期间容忍 TTL 过期，可开启 `setReuseExpiredIPEnabled:YES`。
- 使用 `getSessionId()` 并与选用 IP 一同记录，便于排障。

## 源码构建
执行 `./build_xc_framework.sh` 生成 XCFramework。脚本会从 `gitlab.alibaba-inc.com` 克隆内部构建工具；外部环境建议优先使用 CocoaPods 引入。

## 测试
- 在 Xcode 使用 Scheme `AlicloudHttpDNSTests` 运行。
- 含 OCMock 的用例批量执行可能出现内存问题，请单个运行。
- 非 Mock 用例使用预置参数：AccountID `1000000`，测试域名 `*.onlyforhttpdnstest.run.place`（每年需续期）。

## 依赖与链接
- iOS 10.0+；需链接 `CoreTelephony`、`SystemConfiguration`
- 额外库：`sqlite3.0`、`resolv`；`OTHER_LDFLAGS` 包含 `-ObjC -lz`

## 安全说明
- 切勿提交真实的 AccountID/SecretKey，請通过本地安全配置或 CI 注入。
- 若担心设备时间偏差影响鉴权，可用 `setInternalAuthTimeBaseBySpecifyingCurrentTime:` 校正。

## Demo 与贡献
- 示例应用：`AlicloudHttpDNSTestDemo/`
- 贡献与提交流程请参见 `AGENTS.md`（提交信息与 PR 规范）。
