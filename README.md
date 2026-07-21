# AppMate — iOS & macOS SDK

Swift Package that integrates the [AppMate](https://github.com/fil-technology/appmate) self-hosted retention platform into iOS and macOS apps. On iOS it opens hosted flows inside an `SFSafariViewController`, parses the return deep link, and helps you present Apple's native manage-subscriptions sheet. On macOS the cross-platform core works the same — referrals, onboarding claim, the wishlist API, and deep-link parsing — while in-app Safari presentation, the wishlist *view*, and shake-to-report stay iOS-only (present hosted flow URLs yourself, e.g. in the default browser).

> **Status:** v0.14.0 — Swift Package with zero dependencies, supporting **iOS 16+ and macOS 13+**. cancel, waitlist, feedback, report, contact, crash, onboarding (web-to-app funnel), and referral flows are fully supported on **iOS** via Safari view presentation, deferred-handoff claim, or custom deep link handling. On **macOS** the cross-platform layer is available — referral (share link/code, reward claiming, `redeemReferral`/`redeemReferralFromURL`), onboarding claim, the wishlist API, deep-link parsing, and the App Store subscriptions fallback; in-app flow presentation and the wishlist view remain iOS-only. Referral supports the deferred clipboard handoff, a typed short code (`redeemReferral(code:)`), an installed-app deep-link fast path (`redeemReferralFromURL(_:)`), and surfacing the referrer's own shareable code (`referralShareCode(userId:)`).

## Requirements

- **iOS 16+** — full feature set (StoreKit 2 `AppStore.showManageSubscriptions(in:)`, Safari-presented flows, the wishlist view, shake-to-report)
- **macOS 13+** — cross-platform core: referrals, onboarding claim, wishlist API, deep-link parsing, App Store subscriptions fallback. In-app flow presentation + the wishlist view are iOS-only; on macOS, open hosted flow URLs yourself (e.g. `NSWorkspace.shared.open`) and handle the return deep link.
- Swift 5.9+
- Zero external dependencies

## Install

In Xcode → **File → Add Package Dependencies…** → paste:

```
https://github.com/fil-technology/appmate-ios
```

Pin to `from: "0.14.0"`. Add the `AppMate` product to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/fil-technology/appmate-ios", from: "0.14.0")
```

## Register your URL scheme

In **Info.plist**, add a URL type so AppMate can hand control back to your app:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>myapp</string></array>
  </dict>
</array>
```

Use the same scheme string in `RetentionFlow.configure(...)`.

## Configure

Call once at launch — `@main` `App.init()` or `application(_:didFinishLaunchingWithOptions:)`.

```swift
import AppMate

RetentionFlow.configure(
    .init(
        appSlug: "my-ios-app",
        baseURL: URL(string: "https://cancel.appmate.cloud")!,
        urlScheme: "myapp"
    )
)
```

## Start the cancel flow

When the user taps your **Cancel Subscription** button, call:

```swift
RetentionFlow.startCancelFlow(
    userId: currentUser.id,
    attributes: [
        "plan": "monthly",
        "subscriptionStatus": "active",
    ]
) { link in
    switch link.action {
    case .openPremium(let paywallId):
        navigateToPaywall(variant: paywallId)
    case .openOffer(let offerId):
        // App decides how to present the offer: StoreKit promotional offer,
        // RevenueCat offering, or a custom paywall keyed by offerId.
        OfferRouter.present(offerId)
    case .openSupport(let topic, let message):
        openSupportInbox(topic: topic, prefilled: message)
    case .openFeature(let id): openFeature(id)
    case .returnToApp:        break // user just returns to current screen
    case .manageSubscription:
        Task { await RetentionFlow.presentManageSubscriptions() }
    case .externalURL(let url):
        UIApplication.shared.open(url)
    case .none:
        break
    }
}
```

The SDK presents a Safari sheet, listens for the AppMate deep link emitted at the end of the flow, dismisses the sheet, and invokes your callback on the main actor.

### Soft-fail behaviour

If the AppMate server is unreachable, `onAction` is invoked with `.manageSubscription` so you can route the user straight to the App Store — they're never blocked from cancelling.

## SwiftUI .onOpenURL fallback

If iOS hands your app a deep link via `.onOpenURL` (e.g. user followed the URL outside an active SDK session), parse it manually:

```swift
.onOpenURL { url in
    if let link = RetentionFlow.deepLink(from: url) {
        handle(link)
    }
}
```

## Manage subscriptions

```swift
Task {
    await RetentionFlow.presentManageSubscriptions()
}
```

Tries the in-app StoreKit 2 sheet first; falls back to opening `https://apps.apple.com/account/subscriptions` in Safari if not available (Simulator, no signed-in App Store account, etc.).

## Supported actions

| Action | Triggered when… |
| --- | --- |
| `.returnToApp` | Reason response → "Open app" |
| `.openPremium(paywallId:)` | Reason response → paywall / save-flow route. `paywallId` is set when the dashboard targets a specific variant. |
| `.openOffer(id:)` | Reason response → "Claim offer". The id is opaque — your app maps it to a StoreKit promo / RevenueCat offering / custom paywall. |
| `.openSupport(topic:message:)` | Reason response → "Send feedback" / "Contact support". Both params optional. |
| `.openFeature(id:)` | Reason response → "Open tutorial" (feature id from dashboard) |
| `.manageSubscription` | Any time the user picks the always-visible Manage button |
| `.externalURL(URL)` | Custom external link configured in the dashboard |
| `.onboardingComplete(claimToken:)` | A web-to-app onboarding funnel finished (handled for you by `startOnboardingFlow`) |
| `.none` | Future/unknown action — handle defensively |

## Onboarding funnel (web → app)

An **onboarding funnel** runs on the web — typically from an ad or link-in-bio — *before* the user installs: a few quiz/info screens, an email capture, then an App Store handoff. AppMate persists the answers + email and the iOS SDK recovers them on first launch, so the app opens already personalized. No third-party attribution SDK required.

### Deferred handoff (the common case)

The user finishes the funnel in mobile Safari, taps "Download", installs, and opens the app. On first launch (or right after sign-up, once you have a stable `userId`), call:

```swift
Task {
    if let result = await RetentionFlow.fetchOnboardingResult(userId: currentUser?.id) {
        // result.answers: [stepId: OnboardingAnswer], result.email: String?
        if let goal = result.values(forStep: "goal").first {
            applyStartingPreset(for: goal)
        }
        if let email = result.email {
            prefillSignup(email: email)
        }
    }
}
```

Under the hood the funnel leaves a short claim token (prefixed `amob_`) on the clipboard; `fetchOnboardingResult` reads it, redeems it for the answers, and clears it. Reading the clipboard shows the standard iOS paste banner, so call it at a natural "setting things up" moment.

### In-app funnel

To run the same funnel for an already-installed user (e.g. a "redo setup" button), present it in a Safari sheet — the SDK claims the result for you:

```swift
RetentionFlow.startOnboardingFlow(userId: currentUser.id) { result in
    guard let result else { return } // user dismissed, or claim failed
    apply(result)
}
```

Configure the funnel (steps, copy, App Store URL) in the dashboard or via the MCP `update_onboarding_draft` tool. See the service docs at `/docs/onboarding`.

## Referral (share with a friend)

Real install-attributed referrals: each user gets a unique link **and** a short human-readable code (e.g. `K7Q4-R9XP`), and a friend who installs earns a reward for both sides — tracked server-side and capped. See the service docs at `/docs/referral`.

```swift
// 1. Share — from your "Invite a friend" button.
if let url = await RetentionFlow.referralShareLink(userId: user.id) {
    let message = await RetentionFlow.referralShareMessage(userId: user.id) ?? ""
    presentShareSheet(items: [message, url])
}
// Optional: show a copyable "Your code" chip so people can share the code itself.
if let code = await RetentionFlow.referralShareCode(userId: user.id) {
    yourCodeLabel.text = code   // e.g. "K7Q4-R9XP"
}
// Don't grant the reward on share — it's earned only when a friend installs.

// 2a. New user, deferred handoff — on first launch (shows the paste banner):
if let attr = await RetentionFlow.attributeReferral(userId: user.id),
   let reward = attr.refereeReward {
    FreeAccessManager.shared.grantReferralWeeks(reward.weeks)
}

// 2b. New user, typed code — back an "Enter invite code" field. No clipboard,
//     so NO paste banner. Codes are short + human-readable and tolerant of
//     case/dashes:
if let attr = await RetentionFlow.redeemReferral(code: enteredCode, userId: user.id),
   let reward = attr.refereeReward {
    FreeAccessManager.shared.grantReferralWeeks(reward.weeks)
}

// 2c. New user, ALREADY installed — the invite page opens your app via your
//     URL scheme with the code; redeem it from the inbound URL (no prompt):
.onOpenURL { url in
    Task {
        if let attr = await RetentionFlow.redeemReferralFromURL(url, userId: user.id),
           let reward = attr.refereeReward {
            FreeAccessManager.shared.grantReferralWeeks(reward.weeks)
        }
    }
}

// 3. Referrer — on every launch, claim weeks earned from friends who installed:
let earned = await RetentionFlow.claimReferralRewards(userId: user.id)
if earned.weeks > 0 { FreeAccessManager.shared.grantReferralWeeks(earned.weeks) }
```

> The invite page tries to open your app (via the URL scheme AppMate has on
> file) and falls back to the App Store if it isn't installed. So: **installed**
> users get instant attribution from the deep link (2c); **new** users install,
> then attribute via the clipboard handoff (2a) or a typed code (2b). Register
> your scheme in the AppMate app settings and handle it with `.onOpenURL`.

You get two redemption paths: the deferred clipboard handoff (`attributeReferral`, shows the iOS paste banner — call it at a natural first-launch moment) and the typed-code path (`redeemReferral(code:)`, no clipboard, no banner). `claimReferralRewards` returns each owed week exactly once (the server marks them claimed atomically) and respects the program's lifetime cap.

## QR codes

Every flow has a ready-made QR code — rounded style, your app's logo in the middle, auto-matched to the flow's colour scheme — that opens its public page when scanned. Three ways to present it, lowest to highest level:

```swift
// 1) A URL — hand to AsyncImage
let url = RetentionFlow.qrCodeURL(for: .waitlist)

// 2) A fetched image (UIImage on iOS, NSImage on macOS)
if let img = await RetentionFlow.qrCode(for: .cancel, size: 600) { /* show img */ }

// 3) A drop-in SwiftUI view — the simplest "Scan to …" surface
RetentionFlowQRView(flow: .waitlist)
    .frame(width: 220, height: 220)

// Referral — encode a specific user's invite link:
let code = await RetentionFlow.referralShareCode(userId: user.id)
RetentionFlowQRView(flow: .referral, referralCode: code)
```

`QRFlow` covers every flow: `.cancel .waitlist .feedback .report .contact .onboarding .wishlist .link .referral`. Each method takes `theme: .auto | .light | .dark` (`.auto` matches the flow's colour scheme). It's a plain image fetch — works on **iOS and macOS**, no UIKit required.

## Native forms — feedback, report & contact (iOS + macOS)

Collect **feedback**, **reports**, and **contact** messages with **native UI** instead of (or alongside) the hosted web page — SwiftUI forms that mirror exactly what you configured in the dashboard. Each renders only what you enabled: feedback shows the star rating / message / optional reply-email / custom fields; report shows your category picker + message + optional email; contact shows the name / email / message fields you turned on, plus any custom fields. Nothing the dashboard didn't enable is shown.

```swift
// One-call: sheet on iOS, window on macOS.
RetentionFlow.presentFeedback(userId: user.id) { /* submitted */ }
RetentionFlow.presentReport(userId: user.id)   { /* submitted */ }
RetentionFlow.presentContact(userId: user.id)  { /* submitted */ }

// Or embed the view anywhere — a tab, your own sheet, a navigation push:
FeedbackView(userId: user.id) { dismiss() }
ReportView(userId: user.id)   { dismiss() }
ContactView(userId: user.id)  { dismiss() }

// Or drive it yourself with the typed API (build any UI):
let fb = try await RetentionFlow.feedbackForm()   // published config + app brand
try await RetentionFlow.submitFeedback(message: "Love it", rating: 5)

let rp = try await RetentionFlow.reportForm()      // includes the category list
try await RetentionFlow.submitReport(category: "bug", message: "Crash on launch")

let ct = try await RetentionFlow.contactForm()
try await RetentionFlow.submitContact(email: "me@example.com", message: "Hi!")
```

Each accepts a `flowSlug:` to target a non-primary flow (omit for the primary). The hosted web flow still works (open the page in a Safari sheet) — these are additive **native** paths. iOS 16+ / macOS 13+.

## Crash reports (iOS + macOS)

Let users report a crash with a **native form** — device model, OS version, and app version/build attach automatically (with a visible summary + opt-out toggle in the form), and everything lands in the dashboard's crash inbox with a `new → reviewed → resolved` triage status.

```swift
// One-call: sheet on iOS, window on macOS.
RetentionFlow.presentCrashReport(userId: user.id) { /* submitted */ }

// Or embed the view:
CrashReportView(userId: user.id) { dismiss() }

// Or drive it yourself with the typed API:
let form = try await RetentionFlow.crashReportForm()
try await RetentionFlow.submitCrashReport(
    message: "Crashed while exporting",
    diagnostics: .current()          // device/OS/app snapshot (the default)
)
```

### Attach text logs

> Requires **v0.15.0** — attachments landed after the 0.14.0 tag. Pin
> `from: "0.15.0"` (or `branch: "main"`) to use `CrashAttachment`.

Send small **named text logs** alongside a report — console output, breadcrumbs, a rolling log file. Text only, kept inline server-side (up to 5 attachments, 32 KB each) — no file-storage backend, so no screenshots or binaries.

```swift
try await RetentionFlow.submitCrashReport(
    message: "Crashed on the export screen",
    attachments: [
        CrashAttachment(name: "breadcrumbs", text: recentEvents.joined(separator: "\n")),
        // Read a small text log file (truncated to maxBytes; nil if missing):
        CrashAttachment.file(named: "app.log", at: logFileURL),
    ].compactMap { $0 }
)

// The native form forwards host-provided logs with whatever the user submits:
RetentionFlow.presentCrashReport(attachments: [
    CrashAttachment(name: "breadcrumbs", text: breadcrumbs),
])
```

Attachments show as collapsible sections on each report in the dashboard and are included in the CSV export.

### Detect crashes and offer a pre-filled report on next launch

Best-effort capture of uncaught `NSException`s (name + reason + call stack) and fatal signals (`SIGSEGV` & friends — signal name only). The SDK never uploads anything by itself — the capture is stored locally and offered to *the user* on the next launch:

```swift
// At launch, right after RetentionFlow.configure(_:):
RetentionFlow.enableCrashDetection()

// Later (e.g. on your first screen's .task):
if RetentionFlow.pendingCrash != nil {
    RetentionFlow.presentCrashReport()      // banner + capture pre-filled
    // …or decline it silently:
    // RetentionFlow.clearPendingCrash()
}
```

A submitted or cleared capture is removed; the shake menu can also carry a `.reportCrash()` item. This is a prompt-to-report aid, not a full crash reporter (no symbolication or mach-exception handling) — pair it with your usual crash tooling if you need that.

## Demo app

`Examples/RetentionFlowDemo/` ships a 30-line SwiftUI app showing the integration. Open it from Xcode and edit `RetentionFlowDemoApp.swift` with your own `appSlug` / `baseURL` to test against your AppMate instance.

## Companion repo

The service that hosts the flow + dashboard: <https://github.com/fil-technology/appmate>.

## License

Proprietary — all rights reserved.
