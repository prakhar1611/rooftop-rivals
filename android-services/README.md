# Kite Google Services: real Android SDK plugin, TEST ads only

Build output (not tracked): `build/kite-google-services.aar`. Run `python3 fetch_compile_deps.py` followed by `./build_thin_aar.sh` to generate it from the included source. This is a **thin AAR**, not an installable app. It contains compiled Godot plugin code and manifest, not bundled third-party SDKs. APK integration must resolve all runtime dependencies from Google Maven/Maven Central. Copy this AAR and `KiteGoogleServices.gdap` into Godot `android/plugins`, enable the plugin, and export with the Android Gradle build. Alternatively include the Android library project and its implementation dependencies directly.

## Public Godot API

Singleton: `KiteGoogleServices`.

- `capabilities()` dictionary: `account` is false without a configured public Google web client ID; `rewarded_ads` always false; `test_rewarded_ads` and `privacy_options` true.
- `configure_google_sign_in(server_client_id: String)` sets a **public OAuth web client ID only**, not a client secret. Empty default. Configuration changes cancel pending login.
- `start_login(operation_id: int)`, `cancel_login(operation_id: int)`, `logout()`; signal `login_result(operation_id: int, authenticated: bool)`.
- `set_test_eligibility(adult: bool, outside_battle: bool, opted_in: bool)`; all false by default. These represent explicit UI gates, not an inference of age. Underage/unknown must map to false. No SDK request is initiated by setting these.
- `start_test_rewarded(operation_id: int)` only after explicit TEST button tap; signal `test_reward_result(operation_id: int, earned: bool, message: String)`.
- `test_ad_status(message: String)` for optional status UI.
- `stop_ads()` invalidates callbacks and discards loaded references. It cannot forcibly close an already visible Google full-screen ad or retract a network request already transmitted. A revoked/cancelled operation cannot earn even if the SDK later calls back.
- `show_privacy_options()` opens Google's privacy options only when UMP reports it required; otherwise emits a status message. Expose this visibly in settings.
- Production bridge compatibility: `show_rewarded(id, placement)` emits unsuccessful `reward_result(id, "")`; `is_reward_verified` always returns false. **Never route test rewards into production entitlements.**

## Ads privacy and safety

Only official sample AdMob app ID `ca-app-pub-3940256099942544~3347511713` and rewarded test unit `ca-app-pub-3940256099942544/5224354917` appear. No banners, interstitials, live units, automatic ad request, automatic retry, or prefetch. Reward is recorded only in `OnUserEarnedRewardListener` and delivered after dismissal if eligibility and operation generation still match. A failed/dismissed/unrewarded ad earns nothing. All rewards must be visibly DEMO, without cash, financial or real-world value.

Each explicit test request runs UMP consent update, required form, `canRequestAds`, then SDK initialization/load. A local opt-in is **not** substituted for UMP consent. UMP update/form errors fail closed. This preview does not force EEA debug consent or pretend that consent succeeded. Google's sample app ID may not have a publisher-configured privacy message, so consent behavior must be tested in the intended regions on a real configured test setup.

The manifest removes `com.google.android.gms.permission.AD_ID` and delays app measurement initialization with `DELAY_APP_MEASUREMENT_INIT=true`. The upstream MobileAdsInitProvider is removed through manifest merging to avoid its automatic startup entry point. Explicit MobileAds.initialize remains after the UMP gates; successful resource merge alone does not establish runtime compatibility. This removal must be tested on device before release. No `MobileAds.initialize`, consent update, ad load, or Google Credential Manager call is made in the plugin constructor. These source checks **do not prove zero SDK startup traffic**, nor prevent SDK collection of other device/network information after opt-in. Verify merged manifest and observe device network traffic before any privacy claim or release. The SDK is not an analytics-free guarantee. No personal data or token logging is added by this plugin.

## Google sign-in

Uses AndroidX Credential Manager and Google ID `GetSignInWithGoogleOption`, not deprecated GoogleSignInClient. A fresh cryptographic nonce is generated per request. Credential result is parsed, then discarded without being emitted to Godot, logged, written to disk or stored in preferences. The UI success indicates that Google returned a credential; it does **not** authorize backend operations or represent verified server access. No cloud save or account-bound reward is implemented. Cancellation generation guards suppress late success. Logout cancels pending requests and requests Credential Manager state clearing; it does not delete or globally sign out the user's Google account.

To enable, a developer must configure a legitimate Android OAuth client using package name + signing certificate and its corresponding **web/server client ID**, Google consent screen/testing access, and any required publication verification. Pass only that public web ID in `res://config/google_sign_in.json`. This build ships no client ID, client secret or backend. Do not fabricate credentials or treat a syntactically valid client ID as proof configuration works.

For production accounts, implement server-side token verification (audience, issuer, expiry and nonce binding), TLS exchange and authenticated server session lifecycle. If persisting refresh/session credentials later, use Android Keystore-backed encrypted storage. None are persisted in this version. Production reward entitlements require separate server-side verification and idempotent transaction handling; test callbacks are deliberately ineligible.

## Build and provenance

`python fetch_compile_deps.py` downloads published artifacts from official Google Maven or Maven Central and records URLs, coordinates and SHA-256 in `build/dependency-provenance.json`. `./build_thin_aar.sh` compiles real source against these classes and packages the thin AAR. It selects JAVAC, JAVA_HOME/bin/javac, or a JDK17+ compiler on PATH, in that order. The verified build used JDK21 with source/target17. Python3 is required. The fetcher creates its own output directories; every compile uses fresh temporary class output and deterministic ZIP entries, avoiding stale classes. The compiler warns that a Java17 system-module path was not provided; the code uses Android-compatible APIs. Godot 4.6.3.stable and Robolectric's published Android14 framework JAR are **compile-only**, never packaged into Android output. This standalone compilation requires no Android SDK license files and does not fabricate them. The full APK route uses a genuine Android SDK separately with user-authorized license acceptance.

Pinned runtime roots: Google Mobile Ads 25.5.0, UMP 4.0.0, Credential Manager 1.6.0, credentials-play-services-auth1.6.0, GoogleID 1.2.1. These are pinned known published versions, not a claim of latest release. Before shipping, review SDK support/deprecation policy, transitive dependency tree, licenses, privacy policy, Play Data Safety, audience/content rating, and advertising disclosures.

## Verification status

- Real Java compilation and AAR packaging: performed for the original preview. Rebuild locally to create your own `build/SHA256SUMS`.
- Source safety assertions: `python test_contract.py`.
- APK resource/manifest merge and signing: passed for the original preview APK. Generated verification logs are not included in this source repository. Standalone AAR compilation alone does not establish these.
- Real-device UMP, Google credential UI, cancellation, activity recreation, full-screen ads, reward callback and network behavior: **not exercised** in this environment. Required before release. Test load failure, no-network, back/cancel, privacy revocation mid-load, repeated taps, entering battle, logout while pending, and no double reward. Also verify no AD_ID permission in the final APK.

### Version support review (2026-11-07)

Official Google Maven metadata returned Ads **25.5.0**, UMP **4.0.0**, Credentials **1.6.0 stable** (1.7 alpha excluded), and Google ID **1.2.1**. This source and AAR were recompiled against those versions. Ads25 uses `play-services-ads-api` rather than the old same-version ads-lite artifact. The standalone compile fetcher includes that API AAR; Gradle resolves it transitively. The older first-pass23.6 artifacts, if still present under `deps/old`, are not on the compilation classpath and must not be packaged.

Google's [support schedule](https://developers.google.com/admob/android/deprecation), updated2026-11-05, labels v23 deprecated since2026-02-17, sunset2027-06-30. The selected v25 is supported, with deprecation2027-06-30 and sunset2028-06-30. Its next-generation SDK migration should be reviewed before release; this is a supported legacy SDK, not a claim that no future migration is needed.

### JNI and initialization details

Godot 4.6.3 exposes registered Java plugin methods via `has_java_method`, so adapters should use that if available, falling back to `has_method` only for nonnative mocks. `long` method arguments map to Godot INT in official `jni_utils.cpp`. `SignalInfo` must use boxed `Long.class` and `Boolean.class`, because GodotPlugin validates emitted objects with `Class.isInstance`. Native registration metadata maps these boxed names to OBJECT, but native emission converts actual boxed values via `_jobject_to_variant`; real-device callback testing remains required. Switching to primitive `long.class`/`boolean.class` would fail the Java isInstance check.

Initialization has a 35-second watchdog. If the SDK initialization state is available, it recovers without duplicate loading; otherwise the current test request fails with an explicit restart message. Later requests recheck SDK initialization status. The plugin does not initiate a second potentially concurrent initialization. If the SDK never becomes initialized, restarting the app is the recovery path. `stop_ads` cannot undo SDK initialization already started. No background retry is scheduled.

### UMP test configuration blocker

Google's public sample AdMob app ID is not a substitute for a publisher's configured Privacy & messaging app. It may return a publisher configuration error or no usable consent form; this preview intentionally fails closed and must not bypass UMP to force an ad to display. We have **not demonstrated that this sample app ID can complete UMP and show a real test ad**.

To validate the entire flow, the owner may need an explicitly approved real AdMob **app identity** and configured/published privacy message, while keeping the rewarded **ad-unit ID the official sample test unit**. The owner must provide/approve the app identity and AdMob setup; this plugin does not create accounts, publish privacy messages, add live ad units, or silently replace the sample app ID. A real app ID identifies the publisher app and is distinct from a live ad unit, but changing it is outside this preview's authorization. Google's UMP Android guide: https://developers.google.com/admob/android/privacy . Region-specific debug geography/test-device configuration may also be needed for device QA, and is not enabled automatically.

### Foreground presentation gate

The final implementation splits UMP `loadConsentForm` from `form.show` when consent status is REQUIRED. It rechecks the operation generation and resumed/nonfinishing/nondestroyed Activity immediately before showing. Ordinary backgrounding invalidates pending work, including a form still loading. Only an actually presenting consent form or full-screen ad is exempt from the plugin's pause cancellation so its own overlay cannot accidentally cancel itself. Ad loading/showing is also foreground-guarded. If a consent callback arrives before resume, the safe outcome is a retry message, never a delayed automatic presentation. Device lifecycle QA is still required.

Native cancellation now emits a failed test result immediately for tracked pending operations, clearing the facade spinner. Destruction suppresses the cancellation emission because the engine may already be tearing down.


### Final manifest and build fixes

The library Gradle configuration uses AGP8.9.2, compile/targetSDK36 and minSDK24. The manually packaged AAR manifest explicitly includes its package and uses-sdk min24/target36; without that target, the merger can infer target1 and introduce obsolete storage/phone permissions. Explicit merger removals additionally forbid READ/WRITE_EXTERNAL_STORAGE, READ_PHONE_STATE, AD_ID, and AdServices AD_ID/ATTRIBUTION/TOPICS permissions.

The game implements only Google ID login, not passkey/biometric authentication, and contains no foreground worker or service path. Accordingly this candidate removes USE_BIOMETRIC, USE_FINGERPRINT, FOREGROUND_SERVICE, and the unused AndroidX WorkManager SystemForegroundService component. WAKE_LOCK remains a transitive WorkManager/video dependency. These are targeted preview reductions, not a generic rule for all Credential Manager/WorkManager apps; real-device sign-in and ad playback must confirm compatibility before release. Do not add foreground jobs or biometric/passkey features without restoring and reviewing their required manifest entries.

Fixed UMP/ad failure strings now include the numeric SDK error code only. No provider error text, tokens or personal data is logged or displayed. The final merged APK manifest remains the authoritative permission check; standalone source assertions cannot prove merge results.
