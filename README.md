# AppMate — iOS SDK

Swift Package that integrates the [AppMate](https://github.com/fil-technology/appmate) self-hosted retention platform into iOS apps. Opens the hosted pre-cancel flow inside an `SFSafariViewController`, parses the return deep link, and helps you present Apple's native manage-subscriptions sheet.

> **Status:** v0.1.0 — pre-cancel flow only. Onboarding, trial-expiry, and win-back flows are on the roadmap and will land as additive APIs.

## Requirements

- iOS 16+ (needs StoreKit 2 `AppStore.showManageSubscriptions(in:)`)
- Swift 5.9+
- Zero external dependencies

## Install

In Xcode → **File → Add Package Dependencies…** → paste:

```
https://github.com/fil-technology/appmate-ios
```

Pin to `from: "0.1.0"`. Add the `AppMate` product to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/fil-technology/appmate-ios", from: "0.1.0")
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

## Start the pre-cancel flow

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
| `.none` | Future/unknown action — handle defensively |

## Demo app

`Examples/RetentionFlowDemo/` ships a 30-line SwiftUI app showing the integration. Open it from Xcode and edit `RetentionFlowDemoApp.swift` with your own `appSlug` / `baseURL` to test against your AppMate instance.

## Companion repo

The service that hosts the flow + dashboard: <https://github.com/fil-technology/appmate>.

## License

Proprietary — all rights reserved.
