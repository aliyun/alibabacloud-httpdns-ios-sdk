# Repository Guidelines

## Project Structure & Module Organization
`AlicloudHttpDNS/` contains the SDK source. Public headers live at the module root and under `Model/`, `Log/`, and `Config/`; implementation code is split by responsibility in `Network/`, `Persistent/`, `Scheduler/`, `IpStack/`, and `Utils/`. `AlicloudHttpDNSTestDemo/` is the sample app. `AlicloudHttpDNSTests/` holds XCTest targets grouped by area, including `HighLevelTest/`, `Network/`, `DB/`, `IPDetector/`, and shared helpers in `Testbase/`. Packaging files live at the root: `AlicloudHTTPDNS.podspec`, `Podfile`, `build_xc_framework.sh`, and `resource/PrivacyInfo.xcprivacy`.

## Build, Test, and Development Commands
- `pod install` installs `OCMock` and refreshes the workspace used by the demo and tests.
- `xcodebuild -workspace AlicloudHttpDNS.xcworkspace -scheme AlicloudHttpDNSTestDemo -destination 'platform=iOS Simulator,name=iPhone 15' build` builds the sample app against the local pod.
- `xcodebuild test -workspace AlicloudHttpDNS.xcworkspace -scheme AlicloudHttpDNSTests -destination 'platform=iOS Simulator,name=iPhone 15'` runs the main test suite.
- `xcodebuild test ... -only-testing:AlicloudHttpDNSTests/HttpdnsNWHTTPClientTests` is the fastest way to verify network client regressions.
- `cd AlicloudHttpDNSTests/Network && python3 mock_server.py` starts the local mock server used by integration tests.
- `./build_xc_framework.sh` produces an XCFramework, but it depends on an internal Alibaba build helper cloned at runtime.

## Coding Style & Naming Conventions
This repository is Objective-C first. Follow the surrounding Xcode style: 4-space indentation, braces on the same line, `#pragma mark` for larger sections, and small focused methods. Match existing naming: public API types usually use `HttpDns...`, internal classes commonly use `Httpdns...`, and constants/macros stay uppercase. No repository-wide formatter is configured, so keep diffs minimal and align with nearby files.

## Testing Guidelines
Use XCTest with OCMock. Add the smallest regression test that proves the behavior change and place it in the matching folder. Network changes belong under `AlicloudHttpDNSTests/Network/`; cache, DB, and resolver behavior should extend `HighLevelTest/`, `DB/`, or `IPDetector/`. Name files like existing tests (`*Test.m` or `*Tests.m`) and prefer explicit methods such as `testResolveHostSync_UsesPersistentCache`.

## Commit & Pull Request Guidelines
Recent history uses conventional prefixes with concise Chinese summaries, for example `fix: 本地缓存类型校验避免调度中心崩溃` and `chore: 发布3.4.1`. Keep PRs narrow and include the problem statement, impacted modules, validation commands, and any API or podspec changes. Add screenshots only when the demo app UI changes.

## Security & Configuration Tips
Do not commit real `AccountID`, `SecretKey`, or `credentials.json`; inject secrets locally or in CI. When public headers, pod metadata, or privacy-related behavior changes, update `AlicloudHTTPDNS.podspec`, `README.md`, and `resource/PrivacyInfo.xcprivacy` in the same PR.
