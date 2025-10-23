# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Install dependencies
pod install

# Build SDK (Release configuration)
xcodebuild -workspace AlicloudHttpDNS.xcworkspace -scheme AlicloudHttpDNS -configuration Release build

# Run all unit tests
xcodebuild test -workspace AlicloudHttpDNS.xcworkspace -scheme AlicloudHttpDNSTests -destination 'platform=iOS Simulator,name=iPhone 15'

# Build distributable XCFramework
sh build_xc_framework.sh
```

**Note:** After creating new Xcode files, wait for the user to add them to the appropriate target before running builds or tests.

## Architecture Overview

This is an iOS HTTPDNS SDK with a multi-layered architecture designed for secure, cached, and resilient DNS resolution over HTTP/HTTPS.

### Core Architecture Layers

**1. Public API Layer (`HttpdnsService`)**
- Singleton facade providing three resolution modes:
  - `resolveHostSync:` - Blocking with timeout
  - `resolveHostAsync:` - Non-blocking with callbacks
  - `resolveHostSyncNonBlocking:` - Returns cache immediately, refreshes async
- Manages multi-account instances (one per account ID)
- Configuration entry point for all SDK features

**2. Request Management Layer (`HttpdnsRequestManager`)**
- Orchestrates cache lookups before triggering network requests
- Manages two-tier caching:
  - Memory cache (`HttpdnsHostObjectInMemoryCache`)
  - Persistent SQLite cache (`HttpdnsDB`)
- Handles TTL validation and expired IP reuse policy
- Coordinates retry logic and degradation to local DNS

**3. DNS Resolution Layer**
- **`HttpdnsRemoteResolver`**: HTTPS/HTTP requests to Alicloud servers
  - Builds authenticated requests with HMAC-SHA256 signatures
  - Optional AES-CBC encryption for sensitive parameters
  - Parses JSON responses into `HttpdnsHostObject` (IPv4/IPv6)
- **`HttpdnsLocalResolver`**: Fallback to system DNS when remote fails

**4. Scheduling & Service Discovery (`HttpdnsScheduleCenter`)**
- Maintains regional service endpoint pools (CN, HK, SG, US, DE)
- Rotates between endpoints on failure for load balancing
- Separates IPv4 and IPv6 endpoint lists
- Per-account endpoint isolation

**5. Data Flow (Synchronous Resolution)**
```
User Request
  → Validate & wrap in HttpdnsRequest
  → Check memory cache (valid? return)
  → Load from SQLite DB (valid? return)
  → HttpdnsRemoteResolver
      - Build URL with auth (HMAC-SHA256)
      - Encrypt params if enabled (AES-CBC)
      - Send to service endpoint
      - Parse JSON response
      - Decrypt if needed
  → Cache in memory + DB
  → Return HttpdnsResult

On Failure:
  → Retry with different endpoint (max 1 retry)
  → Return expired IP (if setReuseExpiredIPEnabled:YES)
  → Fall back to local DNS (if setDegradeToLocalDNSEnabled:YES)
  → Return nil
```

### Authentication & Encryption

**Request Signing:**
- All sensitive params signed with HMAC-SHA256
- Signature includes: account ID, expiration timestamp, domain, query type
- Params sorted alphabetically before signing
- Expiration: current_time + 10 minutes

**Request Encryption (Optional):**
- Domain name, query type, and SDNS params encrypted with AES-CBC
- Encrypted blob included as `enc` parameter
- Only encrypted when `aesSecretKey` provided at init

### Key Internal Components

- **`HttpdnsHostObject`**: Internal model with separate IPv4/IPv6 arrays, TTLs, timestamps
- **`HttpdnsResult`**: Public-facing result model (simplified view)
- **`HttpdnsHostRecord`**: Serializable model for SQLite persistence
- **`HttpdnsIpStackDetector`**: Detects network stack type (IPv4/IPv6 capability)
- **`HttpdnsReachability`**: Monitors network changes, triggers pre-resolution
- **`HttpdnsUtil`**: Crypto utilities (HMAC, AES), IP validation, encoding

### Concurrency Model

- Concurrent queues for async user requests and DNS resolution
- Serial queue for network stream operations
- `dispatch_semaphore_t` for blocking synchronous calls
- `HttpDnsLocker` prevents duplicate concurrent resolution of same domain

## Coding Conventions

**Style:**
- 4-space indentation, no trailing whitespace
- Braces on same line as control statements; body starts on next line
- Always use braces for control statement bodies, even single statements
- Comments in Chinese, only for complex logic explaining WHY

**Naming:**
- Types/files: `UpperCamelCase` (e.g., `AlicloudHttpDNSClient.h`)
- Methods/variables: `lowerCamelCase`
- Constants: `kAC...` prefix
- Internal headers: `+Internal.h` suffix

**Commit Messages:**
- Use conventional prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `config:`
- Write in Chinese
- After `git add`, run: `/Users/xuyecan/.macconfig/script/strip-trailing-ws-in-diff --staged`

## Testing Notes

- Test target: `AlicloudHttpDNSTests`
- OCMock-based tests may have memory issues when run in batch - run individually if needed
- Non-mock tests use predefined credentials:
  - Account ID: `1000000`
  - Test domains: `*.onlyforhttpdnstest.run.place` (renewed annually)
- Never commit real production Account IDs or Secret Keys
- Test file naming mirrors class under test (e.g., `AlicloudHttpDNSClientTests.m`)

## SDK-Specific Notes

**Multi-Account Support:**
- Each account ID gets isolated singleton instance
- Separate endpoint pools, caches, and configurations per account

**Public vs Internal Headers:**
- Public headers listed in `AlicloudHTTPDNS.podspec` under `public_header_files`
- Internal headers use `+Internal.h` suffix and are not exposed
- Umbrella header: `AlicloudHttpDNS.h` imports all public APIs

**Required System Frameworks:**
- `CoreTelephony`, `SystemConfiguration`
- Libraries: `sqlite3.0`, `resolv`, `z`
- Linker flags: `-ObjC -lz`

**Pre-Resolution Strategy:**
- Call `setPreResolveHosts:byIPType:` at app startup for hot domains
- Automatically re-triggered on network changes (WiFi ↔ cellular)
- Batch requests combine multiple hosts in single HTTP call

**Persistence & Cache:**
- SQLite DB per account in isolated directory
- Enable with `setPersistentCacheIPEnabled:YES`
- Automatic expiration cleanup
- Speeds up cold starts with pre-cached DNS results
