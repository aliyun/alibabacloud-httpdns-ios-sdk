# Repository Guidelines

This document helps contributors work efficiently on Alicloud HTTPDNS for iOS. It captures how the repo is organized, how to build and test, and the conventions expected for code and reviews.

## Project Structure & Module Organization
- `AlicloudHttpDNS/`: SDK source (Objective‑C). Public headers live here; internal headers use `+Internal.h`.
- `AlicloudHttpDNSTests/`: Unit tests and fixtures.
- `AlicloudHttpDNSTestDemo/`: Demo app to validate SDK behavior.
- `AlicloudHTTPDNS.podspec`: CocoaPods spec.
- Scripts: `build_xc_framework.sh`, `run-sonar.sh`, `clean_up_white_space_line.sh`.

## Build, Test, and Development Commands
- Install deps: `pod install` (uses `Podfile` to resolve Pods).
- Build SDK: `xcodebuild -workspace AlicloudHttpDNS.xcworkspace -scheme AlicloudHttpDNS -configuration Release build`.
- Run tests: `xcodebuild test -workspace AlicloudHttpDNS.xcworkspace -scheme AlicloudHttpDNSTests -destination 'platform=iOS Simulator,name=iPhone 15'`.
- XCFramework: `sh build_xc_framework.sh` (produces distributable framework).

## Coding Style & Naming Conventions
- Indentation: 4 spaces; no trailing whitespace. Run `/Users/xuyecan/.macconfig/script/strip-trailing-ws-in-diff --staged` after staging.
- Braces: always on the same line as control statements; body on the next line, even for single statements.
- Comments: only for complex logic, and in Chinese.
- Naming: Objective‑C types and files use UpperCamelCase (e.g., `AlicloudHttpDNSClient.h/m`); methods/variables use lowerCamelCase; constants `kAC…`.

## Testing Guidelines
- Framework: Xcode unit tests in `AlicloudHttpDNSTests`.
- Naming: mirror class under test (e.g., `AlicloudHttpDNSClientTests.m`).
- Coverage: keep or raise current project coverage; add tests for bug fixes and new APIs.

## Commit & Pull Request Guidelines
- Commit messages (Chinese) use conventional prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `config:`.
- PRs include: concise description, linked issues, test evidence (logs or screenshots for demo), and notes on risk/rollout.
- After `git add`, run the trailing‑whitespace script above; keep diffs minimal and focused.

## Agent‑Specific Notes
- Do not trigger builds/tests for newly created Xcode files until added to intended targets.
- Prefer dry‑runs for commands that modify environments; avoid destructive actions without explicit instruction.
