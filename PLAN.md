# Screen Limiter — POC Plan

Goal: count time spent in **apps** (iOS, iPadOS, macOS) and **websites** (Safari, Chrome, Firefox), and enforce daily limits in **two modes**, each with one budget shared across all devices:
- **Single limit**: one app or site, e.g. "YouTube 30 min".
- **Category limit**: many apps/sites under one budget. Either a built-in category ("Social", "Games") that membership follows automatically, or a custom set ("Video" = YouTube + Netflix).

**Decided**
- Self-control tool for one person on their own devices, so `.individual` Family Controls authorization and no Family Sharing.
- Budgets are per limit and **combined across Mac + iPhone + iPad**, so sync is part of the POC.
- Targets: **iOS/iPadOS 27, macOS 27**, Xcode 27. No back-deployment.

---

## 1. What the platforms allow (checked against the Xcode 27 SDKs on this Mac)

| Capability | iOS / iPadOS 27 | macOS 27 |
|---|---|---|
| Screen Time frameworks | `FamilyControls`, `DeviceActivity`, `ManagedSettings` available. | SDK ships them, but `DeviceActivityCenter`, `DeviceActivityEvent` and `ManagedSettingsStore` are all marked `@available(macOS, unavailable)`. **No Screen Time engine for third parties on the Mac.** |
| Count app time | Two ways: **(A) data access** (below) gives exact durations + bundle IDs; **(B) tokens only** gives threshold events on opaque tokens. | Do it yourself: `NSWorkspace` frontmost app + idle/lock/sleep. |
| Count website time | Safari domains via Screen Time (A or B). Chrome/Firefox on iOS count as apps. | A WebExtension per browser. |
| Block | `ManagedSettingsStore.shield` (needs tokens). | Hide the app + overlay window; the extension redirects the tab. |
| Limit-reached callback | `DeviceActivityMonitor.eventDidReachThreshold`. | Your own timer. |

### iOS data access (new in iOS 26.4) — changes the design

- Authorization status `.approvedWithDataAccess` + entitlement `com.apple.developer.family-controls.app-and-website-usage` unlock:
  - `FamilyActivityData.shared.installedApplications / visitedWebDomains / activityCategories` → real **bundle IDs, domains and category names**, not only opaque tokens.
  - `DeviceActivityData.activityData(filteredBy:using: .live)` → **exact per-app/per-domain durations, readable in the main app**. Before this, you had to use the sandboxed report extension or the threshold-ladder hack.
- **Restrictions (from Apple's docs):**
  - Customer installs only work on devices **in the EU with an EU Apple Account**.
  - **Development builds work in every region** using an Apple-provided provisioning profile. For a personal tool installed from Xcode onto your own devices, that's all you need.
  - **Only one app per device** can hold data access. Granting it to another app drops yours back to `.notDetermined`.
- Consequence: iOS limits can be defined by **bundle ID/domain strings**, exactly like the Mac. Each device converts a string to its local token (`Application.token`) for shielding, so you **no longer need to re-pick apps on every device**.

### Other iOS 26.4–27 APIs used

- `DeviceActivityEvent(..., threshold:, includesPastActivity: true)`: a threshold registered at 3 pm still counts usage since midnight. This lets you re-register "remaining budget" thresholds mid-day, which was the biggest open question in the previous plan.
- `ManagedSettingsStore.tokensDidExpire` + `ManagedSettingsStore.refresh(&tokens)` (26.5): **tokens can expire**. You must listen for that and refresh them.
- `ManagedSettingsStore(named:)` + `isActive` (26.5): use one named store per limit, and switch it on/off instead of recomputing one global shield set.

### Fallback (B): no data access

If data access is ever unavailable (shipping to non-EU users, or another app took the slot), fall back to tokens + a **threshold ladder**. Events at 5-min steps, switching to 1-min steps in the last 10 min of the budget, record "≥ N min" in the App Group. The POC keeps this as a spike, not the main path.

---

## 2. Identifiers

| | Mac | iOS/iPadOS with data access | iOS fallback (B) |
|---|---|---|---|
| App | bundle ID `com.hnc.Discord` | bundle ID `com.google.ios.youtube` (+ local `ApplicationToken` for shielding) | opaque `ApplicationToken`, device-specific |
| Website | eTLD+1 from the extension, `youtube.com` (optionally a path prefix `youtube.com/shorts`) | domain from `WebDomain` (Safari only) | opaque `WebDomainToken` |
| Category | — (Mac members are listed by hand) | category name, e.g. "Social" | `ActivityCategoryToken` |

### Limit modes

| Mode | Defined by | iOS enforcement | Mac membership |
|---|---|---|---|
| **Single** | one matcher: `bundle:com.google.ios.youtube` or `domain:youtube.com` (with an optional counterpart on the other platform, e.g. YouTube app on iOS + youtube.com on the Mac) | `DeviceActivityEvent(applications: [token])` or `webDomains:` | exact match |
| **Category — built-in** | `category:social`: follows Screen Time's categories on iOS | `DeviceActivityEvent(categories: [categoryToken])`; the system decides membership, including newly installed apps | apps: `LSApplicationCategoryType` from each app's Info.plist (e.g. `public.app-category.social-networking`), mapped to the iOS category; sites: a bundled seed list of domains per category |
| **Category — custom** | a set of matchers the user picks | one event with all members' tokens | exact matches |

All modes allow `excluding:` matchers (e.g. "Social except WhatsApp"). On iOS, excluded apps are left out of the event and the shield. One target can be covered by several limits (YouTube single 30 min + Video custom 60 min + Entertainment built-in 90 min). Its time counts toward every limit that covers it, and it's **blocked as soon as any of them is used up**.

---

## 3. What the POC must prove

| # | Proof point | Pass criteria |
|---|---|---|
| P1 | Mac app tracking | Scripted 30 min: per-app totals within ±5% of a stopwatch; idle > 60 s, lock and sleep aren't counted. |
| P2 | Mac website tracking in Safari, Chrome, Firefox | Per-domain totals within ±5%; only the focused window's active tab counts; no double counting ("Chrome" vs "youtube.com"). |
| P3 | iOS/iPadOS data access | The main app reads today's exact per-bundle/per-domain durations via `activityData(.live)`; they match the Settings → Screen Time numbers within 1 min. |
| P4 | Limit modes | One single limit (YouTube), one built-in category (Social, incl. an app installed after the limit was set), one custom category (Video), with overlap: YouTube counts toward all that cover it and is blocked by whichever runs out first; an `excluding` app stays usable; the limit definition syncs, and each iOS device resolves bundle IDs to tokens without re-picking. The Mac maps Social via `LSApplicationCategoryType` + the domain seed list. |
| P5 | Sync | Each device writes its per-limit daily seconds to CloudKit; every device shows the same combined total within 2 min. |
| P6 | **Combined enforcement** | Budget 20 min: 10 min on the Mac + 10 min on the iPhone (e.g. a custom "Video" limit: youtube.com on the Mac, the Netflix app on the iPhone) → the next use on **any** device is blocked; overshoot ≤ 2 min. Works in both directions and with an iPad in the mix. |
| P7 | Resilience | Blocking still happens with the iOS app killed (monitor extension path); expired tokens are refreshed; the day resets at the configured hour. |

**Out of scope:** tamper resistance (quitting the Mac app, removing extensions), App Store/TestFlight distribution, fallback (B) as a full product path, Chrome/Firefox domains on iOS, polish/onboarding.

---

## 4. Architecture

```
screen-limiter/
├── Packages/LimiterCore/          Swift package (macOS + iOS): Limit, Matcher, DailyUsage, rule engine, CloudKit sync
├── Apps/
│   ├── Mac/                       Menu-bar app (SwiftUI, LSUIElement)
│   │   ├── AppTracker             NSWorkspace + idle/lock/sleep → sessions
│   │   ├── WebBridge              extension events (native messaging + Safari handler)
│   │   ├── Enforcer               hide app + overlay; tell the extension to block domains
│   │   └── NativeHost/            CLI launched by Chrome/Firefox (stdio ↔ XPC to the app)
│   └── iOS/                       Universal iPhone + iPad app
│       ├── UsageReader            activityData(.live) → per-limit seconds
│       ├── TokenResolver          FamilyActivityData: bundleID/domain → token; handle tokensDidExpire
│       ├── MonitorExtension       thresholds → toggle the limit's named ManagedSettingsStore
│       └── ShieldConfigExtension  shield text: "Blocked by Video: 60/60 min across devices"
├── extension/                     TypeScript WebExtension → dist/{chrome,firefox,safari}
└── PLAN.md
```

### Model (`LimiterCore`)

```swift
enum Matcher: Codable, Hashable { case bundle(String), domain(String, pathPrefix: String? = nil), category(CategoryID) }
enum LimitMode: Codable { case single(Matcher, counterpart: Matcher? = nil)   // e.g. iOS app + Mac site
                          case category(CategoryID)                          // built-in, auto membership
                          case custom(Set<Matcher>) }
struct Limit: Codable, Identifiable { let id: UUID; var name: String; var mode: LimitMode; var excluding: Set<Matcher>
                                      var dailyBudget: TimeInterval; var resetHour: Int; var timeZone: TimeZone }
struct DailyUsage: Codable { let limitID: UUID; let day: String; let deviceID: String; var seconds: TimeInterval; var updatedAt: Date }
```

`CategoryID` is our own enum (social, games, entertainment, …). It maps to Screen Time category names on iOS and to `LSApplicationCategoryType` values + the domain seed list on the Mac. The rule engine's `members(of: limit, on: platform)` is the only place the modes differ; everything downstream (usage sums, sync, blocking) works per `Limit`.

CloudKit private DB. `Limit` is edited on any device. `DailyUsage` record name = `"\(limitID)|\(day)|\(deviceID)"`. Each device only writes its own row, so there are no conflicts. Combined total = the sum of that day's rows. Day key = limit `timeZone` + `resetHour`.

### Mac

- Active interval: starts on `didActivateApplicationNotification`; ends on the next activation, `screensDidSleep`, `willSleep`, `com.apple.screenIsLocked`, or idle ≥ 60 s (`CGEventSource.secondsSinceLastEventType`, polled every 5 s).
- Browser frontmost + extension heard from within 20 s → attribute to the domain; otherwise to the browser app.
- Extension sends `{browser, windowFocused, url, ts}` on tab/URL/focus/idle changes + a 15 s heartbeat (`chrome.alarms` in MV3).
- Transport: Chrome and Firefox via native messaging host manifests (`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`, `…/Mozilla/NativeMessagingHosts/`); Safari via `SafariWebExtensionHandler` in the menu-bar app bundle.
- While anything covered by a limit is being used, upload `DailyUsage` every 30 s and pull other devices' rows every 60 s (plus a CloudKit subscription push). Block when `local + remote ≥ budget`.

### iOS / iPadOS

```
                       ┌─────────── CloudKit (Limit, DailyUsage) ◄──── Mac
                       │  silent push             ▲ upload own seconds
                       ▼                          │
 main app (woken by push / BGAppRefresh / opened)
   1. activityData(.live) → this device's seconds per limit → upload
   2. remaining = budget − (this device + other devices)
   3. remaining ≤ 0 → store(named: limit).isActive = true   (shield now)
      else re-register event "limit.<limit>" at thisDevice + remaining, includesPastActivity: true
   4. also register "tick.<limit>" every 5 min of use of the limit's members → wakes the extension to upload
                       │
 MonitorExtension (runs even when the app is killed)
   eventDidReachThreshold("limit.<limit>") → activate the limit's store → shield
   eventDidReachThreshold("tick.<limit>")  → write to the App Group; upload if CloudKit works in-extension (spike)
   intervalDidStart (daily)                → deactivate all stores
```

All members of one limit go in **one** `DeviceActivityEvent` (`applications:` + `webDomains:` + `categories:`), so the system sums them for you. A built-in category limit just passes the category token, and the system tracks membership. Since each limit has its own named store, overlapping limits are simple: iOS combines the active stores, so any exhausted limit blocks.

---

## 5. Milestones

Spikes first. Each is throwaway code answering one question.

| Step | Work | Answers | Est. |
|---|---|---|---|
| **S0** | Join the Apple Developer Program ($99/yr — see §7); enable the Family Controls **and** App-and-Website-Usage capabilities; get the Apple-provided dev profile; App Group; CloudKit container. | Can you get `.approvedWithDataAccess` on your devices at all? | 0.5 d |
| **S1** | iOS: `activityData(.live)` + `FamilyActivityData` in the main app. How fresh is `.live`? Does it work in the monitor extension, or on a background wake? | P3 | 1 d |
| **S2** | iOS: one event with `includesPastActivity: true`, re-registered mid-day; named store `isActive` toggle; shield appears with the app killed. | P6/P7 feasibility | 1 d |
| **S3** | iOS: CloudKit write from the monitor extension (memory limit); silent-push latency to the iPhone. | P5 latency | 1 d |
| **S4** | Mac: CLI logging frontmost app + idle/lock/sleep. | P1 | 0.5 d |
| **S5** | Extension → native side in Chrome, Firefox, Safari. | P2 transport | 1.5 d |
| **S6** | (Fallback B) threshold ladder accuracy without data access. | Plan B viability | 0.5 d |
| **S7** | **Screen Time bridge** (Mac, free account): a menu-bar app hosts an `STWebpageController` and sets its `URL` to the Chrome/Firefox active tab reported by the extension. Questions: (a) does Screen Time record the usage if the controller's view is in a tiny or hidden window? (b) does it show under Websites, count toward a website limit set in System Settings, and sync via Share Across Devices? (c) does `urlIsBlocked` flip when the limit hits, so the extension can block the tab? (d) does `setBundleIdentifier("com.google.Chrome")` work, or is the usage credited to our app? If (a)–(c) pass, **Apple's Screen Time becomes the engine** and most of M4–M6 can go. **Results 2026-10-01: (a) ✅ any window works, even 1×1 at alpha 0, but no window = no verdict. (b) ✅ Screen Time counts the usage and fires the limit. (c) ✅ `urlIsBlocked` flips 0.2–0.4 s after the URL is set; the extension closes the tab. Caveats: only the *first* `STWebpageController` per process works (keep one forever); the verdict is evaluated when the URL is set (re-submit every 10 s for limits that run out mid-page) and is stale for ~0.4 s after a URL change. (d) ❌ fails:** `setBundleIdentifier` is "only supported for registered web browsers" (Apple-managed, likely tied to the `com.apple.developer.web-browser` entitlement), so usage is credited to Screen Limiter, not Chrome. | Architecture shortcut | 0.5 d |
| **M1** | `LimiterCore`: model, `members(of:on:)` for single/category/custom + excluding, overlap rule engine, category map (iOS names ↔ `LSApplicationCategoryType` ↔ domain seed list), unit tests. | P4 | 2 d |
| **M2** | Mac: AppTracker + today view per app/domain/limit. | P1 | 1.5 d |
| **M3** | Mac: WebBridge + de-dup + 3-browser extension build. | P2 | 2 d |
| **M4** | CloudKit sync (Limit + DailyUsage, subscriptions, polling backstop) on Mac and iOS. | P5 | 2.5 d |
| **M5** | iOS app: limit editor with a Single / Category / Custom picker (installed apps, visited domains, categories from `FamilyActivityData`), UsageReader, TokenResolver + expiry refresh. | P3, P4 | 2.5 d |
| **M6** | Enforcement: Mac Enforcer + extension blocking; iOS monitor extension + named stores + threshold re-registration. | P6, P7 | 2.5 d |
| **M7** | Test run of P1–P7 (all three modes + overlap, Mac → iPhone, iPhone → Mac, iPad, app killed, day rollover) + a write-up of the gaps. | all | 1 d |

About 4 weeks for one developer. Order tip: S4, S5, M2 and M3 are Mac-only and need no paid account, so you can start there and join the program when you reach the iOS work.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| Data access needs an Apple-provided dev profile you can't get | S0 finds out on day 1. If blocked, fall back to plan B (tokens + ladder; you pick apps per device). |
| Another app on your phone takes the one data-access slot | Detect `.notDetermined`, show a banner, fall back to B until re-granted. |
| `activityData(.live)` is slow or doesn't work in the background/extension | Enforcement doesn't depend on it: thresholds live in the system. Worst case, upload only happens when the app wakes up, so Mac → iOS is fast and iOS → Mac is slower. S1/S3 measure it. |
| Dev-signed builds expire (1 year with a paid account) | Fine for personal use; re-install from Xcode. |
| DeviceActivity events flaky (widely reported since iOS 26) | Re-register on every app wake; the Mac-side and `activityData` numbers let you detect a missed event and shield from the main app. |
| Silent pushes throttled or dropped | The Mac polls; iOS re-checks on `BGAppRefreshTask` and on every tick event. |
| Tokens expire (iOS 26.5+) | Handle `tokensDidExpire` → `refresh`; resolve from bundle IDs again. |
| MV3 service worker suspends | Mac treats a heartbeat older than 20 s as "attribute to the browser app". |
| You bypass the limit (quit the Mac app, disable extensions) | Out of scope for the POC; gaps are logged. |

## 7. Why a paid account

Not because of data access specifically. Apple's capability table lists these as **Apple Developer Program only** (not available to a free Personal Team):

| Capability | Needed for |
|---|---|
| Family Controls (development) | anything Screen Time on iOS; data access is layered on top of it |
| App Groups | sharing state between the iOS app and the monitor/shield extensions |
| iCloud: CloudKit | cross-device sync |
| Push Notifications + Background Modes | waking iOS when another device's usage changes |

Free provisioning profiles also expire after 7 days. The Mac tracker and the Chrome/Firefox extensions work on a free account. For Safari, enable unsigned extensions in Safari's developer settings during development.

## 8. Open question

1. Are you in the EU (with an EU Apple Account)? It doesn't matter for the POC, since dev builds work anywhere. It only matters if you ever want to install this through TestFlight or the App Store, where data access is EU-only and non-EU installs need plan B.

---

## 9. Existing tools (checked Oct 2026)

| Tool | Apps on iOS | Mac apps | Mac sites in Chrome/Firefox | One budget across devices | Gap |
|---|---|---|---|---|---|
| **Apple Screen Time** (built in, free) | ✅ single + category limits | ✅ | ❌ Safari only on the Mac | ✅ with "Share Across Devices" | Chrome/Firefox on the Mac are invisible; "Ignore Limit" is one tap |
| **Freedom** ($40/yr) | blocklist sessions | ✅ sessions | "Limit" extension: per-browser daily limit, no Safari | ❌ sessions sync, budgets don't | blocks on a schedule, doesn't count a shared budget |
| **Opal** ($100/yr) | ✅ strong | sessions only; app limits "later" | via the Mac app | ❌ data stays on each device | no sync |
| **Cold Turkey** ($39 once) | ❌ | ✅ | ✅ | ❌ | desktop only |
| **Jomo, one sec, ScreenZen, Clearspace** | ✅ | partial or none | ❌ / partial | ❌ | iOS-first |
| **Browser extensions** (ScreenLimit, YouTube Time Limiter) | ❌ | ❌ | one browser | ❌ | one browser |

**Nobody does the full combination** (one budget across iOS apps + Mac apps + Mac Chrome/Firefox/Safari). The closest is Apple's own Screen Time if you only use Safari on the Mac.

## 10. Is $99 worth it?

- **Break-even:** after Apple's 15% Small Business cut, a $20/yr subscription nets about $17, so **6 paying users cover the $99/yr**. Or count it as a personal tool replacing Freedom + Opal (~$140/yr), which still wouldn't cover your use case.
- **The market is proven:** Opal reports 1M+ DAU and $10M+ ARR on iOS alone. Users routinely pay $20–100/yr in this category.
- **Against:**
  - The App Store is crowded with iOS blockers.
  - Apple could close the gap by tracking Chrome on the Mac (Chromium has an open ScreenTime ticket).
  - Distribution needs Apple's Family Controls approval.
  - Exact iOS numbers (data access) are EU-only for shipped apps; elsewhere you'd ship plan B.
- **Niche to target:** Mac users who use Chrome or Firefox and also have an iPhone (developers, students, knowledge workers). Pitch: *"one budget everywhere, any browser."*
- **Cheap validation:** build the Mac side first on a free account (S4/S5/M2/M3), post it to r/nosurf, r/digitalminimalism and a Show HN, and pay the $99 once people ask for the iPhone side.
