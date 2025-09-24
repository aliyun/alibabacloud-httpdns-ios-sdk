# Support Multi‑Tenants Plan (HttpDnsService Multiton)

## Goals
- Add multi‑account support with minimal surface change.
- Preserve full backward compatibility: existing apps keep using `sharedInstance`.

## User‑Visible API
- New: `+ (nullable instancetype)getInstanceByAccountId:(NSInteger)accountID;`
- Existing: `+ sharedInstance` returns the first initialized account’s instance.
- Existing initializers `initWithAccountID:…` keep behavior; if the account already exists, return the existing instance and do not overwrite its secrets/config.

## Behavior Rules
- First call to any initializer creates the first instance and sets it as `sharedInstance`.
- Multiple calls with the same `accountID` return the same instance.
- `getInstanceByAccountId:` returns a registered instance or `nil` if not initialized for that `accountID`.

## Internal Architecture
- Multiton registry inside `HttpDnsService`:
  - Static map: `accountID -> HttpDnsService` guarded by a serial queue.
  - Static weak `firstInstance` for `sharedInstance`.
- Per‑instance state (no global cross‑talk):
  - `HttpdnsRequestManager` (owns its in‑memory cache).
  - `HttpdnsDB` (already per account via file name).
  - Delegates/config: TTL delegate, logging handler, degrade flags, cache settings.
- Request context:
  - `HttpdnsRequest` adds `accountId` and is assigned at call sites inside `HttpDnsService`.
- Remote resolver:
  - Stop reading global singleton. Resolve context by `request.accountId` → `[HttpDnsService getInstanceByAccountId:…]` to access `accountID/secretKey/aesSecretKey/authTimeOffset`.
- Scheduler/region (decision: shared globally):
  - Keep a single global `HttpdnsScheduleCenter` and one persisted `schedule_center_result` file.
  - Keep global region key `kAlicloudHttpdnsRegionKey` in `NSUserDefaults`.
  - Region changes must clear host caches for all registered accounts and call `resetRegion:` once.
  - Creating additional account instances must not re‑init or override scheduler state; init must be idempotent.

- Network status observation (multicast):
  - Stop assigning `reachability.reachabilityBlock` from managers (last‑wins bug).
  - Each `HttpdnsRequestManager` observes `kHttpdnsReachabilityChangedNotification` and calls its own `-networkChanged`.
  - Ensure `[[HttpdnsReachability sharedInstance] startNotifier]` is called once (idempotent) and remove observers on teardown.

## Request & Pre‑resolve Flow
- Public API on an instance builds `HttpdnsRequest` and stamps `request.accountId = self.accountID`.
- `RequestManager` uses its own cache/DB; pre‑resolve also stamps `accountId` internally.

## Phased Implementation
1) Multiton
   - Add registry, wire `sharedInstance` semantics, adapt initializers, add `getInstanceByAccountId:`.
2) Context propagation
   - Add `accountId` to `HttpdnsRequest`; set it in all call sites; ensure pre‑resolve does the same.
3) Resolver decoupling
   - Refactor `HttpdnsRemoteResolver` to read from the instance via `getInstanceByAccountId:` using `request.accountId`.
4) Reachability multicast
   - Replace single `reachabilityBlock` assignment with NSNotification observers in each manager.
   - Keep `startNotifier` idempotent; unregister observers on dealloc/teardown.
5) Global scheduler hardening
   - Ensure `setRegion:` writes the global key once, resets scheduler once, and iterates all instances to `cleanAllHostCache`.
   - Ensure scheduler init runs once or remains idempotent for later accounts.
6) Hardening & docs
   - Null‑safety when instance is missing; logs. Update README and examples.

## Testing Matrix
- Back‑compat: existing single‑account demo/tests unchanged.
- Dual accounts A/B concurrent:
   - Same host resolves via distinct caches and distinct DB files.
   - Changing degrade/persistent settings on A does not affect B.
   - Pre‑resolve + resolve interleave safely across A/B.
- Global scheduler/region behavior:
   - Calling `setRegion:` on A clears caches for both A and B, scheduler region updates once, only one schedule file exists.
   - Initializing B after A does not change scheduler region or re‑init unexpectedly.
 - Reachability events:
   - Simulate network change; both A/B managers receive notification and execute `-networkChanged`.
   - Verify in‑memory cache of each manager is cleared; pre‑resolve runs only if enabled per account.
   - Ensure scheduler update happens once overall (existing time‑window gating prevents thrash).
- Failure paths: unknown `accountID` to `getInstanceByAccountId:` returns `nil` gracefully.

## Risks & Mitigation
- Hidden global reads: search and remove `[HttpDnsService sharedInstance]` usages from internal code paths that should be per‑instance.
- Memory footprint: one cache/DB per instance; document expected overhead.
 - Reachability last‑wins overwrite: fixed by notification multicast; ensure observers are removed to avoid leaks.

## Acceptance Criteria
- Zero code changes required for single‑account users.
- Two accounts can run concurrently without cache/config pollution.
- `sharedInstance` equals the first initialized instance; `getInstanceByAccountId:` returns the correct object.
