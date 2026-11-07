# Rooftop Rivals — Campaign preview 0.10.0

Source for an **offline single-player Android preview**, built in Godot 4.6.3. The game is a debug preview, not a store-ready release. This repository contains source only, not a prebuilt APK or native plugin AAR. It does not establish commercial viability, retention or revenue.

## What changed

- **12 named rivals across four city-inspired chapters:** Ahmedabad, Jaipur, Lucknow and Varanasi. Sequential rooftop challenges, match briefings, distinct weather and increasingly demanding tactics.
- **Six rule-based opponent styles:** sweeper, patient, pressurer, dancer, reader and champion. Their movement, attack windows and defensive choices differ. No LLM, online inference or gameplay server is involved.
- **Deeper cutting:** crossing angle and height affect leverage; overlong pulls lose bite; controlling tension, easing defensively and responding to telegraphed gusts matter. Live rival intent, position advantage, wind warnings and loss explanations make the rules visible.
- **Replayable medals:** each campaign win earns a medal, with two extra medals for the encounter's clean-cut duration and remaining-line goals. Best results persist. Losing a replay does not remove existing medals.
- **City Cup:** three consecutive rounds against progressively stronger opponents. Winning advances, a loss or draw ends the cup, and the bracket can resume between rounds after closing the app. A resumed round restarts with full string; mid-duel positions are not saved.
- **Six earned kite colours:** Jade, Saffron, Indigo, Rose, Sky Blue and Champion Gold. No paid power, purchases, currency or loot boxes. Every colour plays identically.
- **Guided practice:** steer, make a controlled cut, then release tension. Practice cannot cut either kite and awards no match statistics, medals or cosmetics.
- **Quick duel remains available**, with three difficulties, fresh seeded wind, local scores, optional sound/haptics, left-handed controls and reduced decorative motion.

The four chapters currently share the same procedural 3D rooftop geometry with distinct sky/light/rival colour palettes. They are **not four separately built city maps**. Names and themes are original fictional challenges, not recreations of actual people or locations.

## How to play

1. Open **How to Fly → Start Guided Practice** for the three control lessons.
2. Choose **Campaign** or **Continue Campaign**, read a rival's tip, then challenge them.
3. Steer into a string crossing. Pull while in the marked green tension zone and seek a useful angle. Release before strain builds or a gust hits.
4. Replay completed rivals to improve their medals, or enter the City Cup.

Touch: thumb pad to steer, hold Pull/Cut, hold Release. Desktop: WASD/arrows, Space, Shift; Escape pauses or goes back. Progress is local to this installation. Do not uninstall an old preview unless you accept losing local progress.

## Android build identity

Version name **0.10.0-campaign-preview**, version code **4**, package `org.rooftoprivals.prototype`, ARM64, Android 7/API 24 minimum, target API 36. The separately built preview retained its temporary debug signer for in-place updates of the earlier preview. No signing key or certificate is included in this source repository. **Actual installation/update on a phone has not been tested.**

The prior 0.9.1 profile filename is retained and safely migrated; existing stats/settings/colours are preserved. Invalid or future-version save files are protected rather than silently overwritten. New mode progress has defensive validation and atomic saves. This is local integrity protection, not an anti-cheat or secure server economy.

## Optional Google SDK integrations are preserved

The Android source integrates real Google Mobile Ads **25.5.0**, UMP **4.0.0**, AndroidX Credentials **1.6.0** and Google ID **1.2.1** SDK wiring. Only Google's official sample TEST ad identity/unit are included. No live ad units, automatic ad requests, purchases or production reward entitlements are enabled.

Guest gameplay and progression are independent of these services. Privacy → SDK Test Ads requires an explicit adult-test declaration and a separate session opt-in, then a user-initiated request outside a duel. UMP eligibility is mandatory; consent failures block the request. The sample AdMob app identity may lack usable publisher privacy-message configuration. Successful consent, test-ad display/completion and actual Google sign-in have **not** been demonstrated on a device.

Google sign-in remains unavailable because no legitimate public OAuth server/web client ID is configured. No provider accounts, OAuth clients or live monetization were created. Credential tokens are discarded, not persisted, logged or used for server authorization. Test-ad completion never grants saved game progress.

See `android-services/README.md` for exact SDK contracts and configuration. A production backend must verify authentication/rewards separately.

## Build and test

See `godot/docs/ANDROID_BUILD.md` and `VALIDATION.md`. Use the matching official Godot 4.6.3 Android export template, a compatible Java SDK and Android Platform 36 / Build-Tools 36.1.0. No signing keys, toolchain caches or credentials are included.

First build the native plugin from `android-services/`, then install the Android build template in Godot and configure your local SDK/signing identity. Run `tools/export_android_debug.sh`. See the step-by-step source build instructions in `godot/docs/ANDROID_BUILD.md`. A local build using a different signing key cannot update an existing APK in place.

Review and accept the Android SDK terms for your own local installation: https://developer.android.com/studio/terms . Build tools and SDK license files are not included.

## Release gates that remain

- Physical-device gameplay, visual composition, multi-touch/cutouts, lifecycle, frame-time, battery/thermal and upgrade testing.
- Human playtests: is the control scheme understandable, do losses feel fair, and do players voluntarily replay? Automated bot wins are not evidence of fun or retention.
- Actual Google UMP/test-ad/sign-in sessions, legitimate service configuration, device-network audit, production authentication/reward backend and appropriate privacy controls/disclosures.
- Final audience/age declarations, privacy policy, data safety, permanent branding/package identity, owner-controlled production signing, release AAB, Play testing/review and store materials.
- Multiplayer, cloud saves, leaderboards, distinct city geometry and further game modes are not implemented.

No app has been published or installed on a physical device by this work. Live monetization should wait for gameplay validation and the provider/privacy release gates.
