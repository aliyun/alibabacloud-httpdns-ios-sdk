# Repository Guidelines

## Project Structure & Module Organization
- `AlicloudHttpDNS/`: SDK 源码。核心模块：`Config/`, `Model/`, `Persistent/`, `Scheduler/`, `Utils/`, `IpStack/`, `Log/`。主要类：`HttpdnsService`, `HttpdnsRequestManager`, `HttpdnsLocalResolver`, `HttpdnsRemoteResolver`。
- `AlicloudHttpDNSTests/`: 测试代码。子目录：`Testbase/`, `HighLevelTest/`, `DB/`, `IPDetector/`。
- Scripts: `build_xc_framework.sh`（构建 XCFramework）。依赖通过 CocoaPods 管理（`Podfile`）。

## Build, Test, and Development Commands
- `pod install` / `pod update`: 安装或更新依赖。
- `./build_xc_framework.sh`: 生成通用 XCFramework 产物。
- 测试：在 Xcode 中使用 Scheme `AlicloudHttpDNSTests` 运行；含 OCMock 的用例请单个执行以避免内存问题。

## Coding Style & Naming Conventions
- 目标平台 iOS 10.0+；使用 Xcode 默认格式化，避免未使用的导入。
- 命名：类/类型使用帕斯卡命名（如 `HttpdnsRequestManager`），方法/变量使用小驼峰。
- 花括号：与控制语句同一行起始，且单语句也必须使用花括号。
- 注释：仅为复杂逻辑编写，使用中文；避免多余注释。
- 空白与日志：不得有行尾空白；日志/控制台输出禁止使用表情符号。

## Testing Guidelines
- 测试框架：Xcode 单元测试；复用 `AlicloudHttpDNSTests/Testbase/TestBase.h` 的异步工具。
- 约定：测试文件以 `*Tests.m` 命名，方法以 `test*` 开头；保证独立、可重复，尽量 Mock 网络与持久化。
- 重点覆盖：缓存与 TTL、多线程与调度、数据库读写、IPv4/IPv6 双栈与降级路径。

## Commit & Pull Request Guidelines
- 提交信息：使用 Conventional Commits 前缀（`feat|fix|docs|refactor|chore|config`）；中文摘要一行，其后空一行并使用项目符号列出要点。
- 提交前：`git add` 后运行 `/Users/xuyecan/.macconfig/script/strip-trailing-ws-in-diff --staged` 清理行尾空白；保持最小化 Diff，避免无关重排。
- PR 要求：清晰描述、关联 Issue、给出验证步骤（必要时附截图/日志）。

## Security & Configuration Tips
- 切勿提交 AccountID/SecretKey；示例使用占位值，在本地或 CI 通过安全方式注入。

## Agent-Specific Notes
- 新建 Xcode 源文件后，先将其添加到目标 Target，再进行构建或测试。
- 优先使用干运行与清晰日志；避免破坏性操作。
