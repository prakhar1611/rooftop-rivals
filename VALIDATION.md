# Verification scope — 0.10.0 campaign preview

## Passed against the final game source

- **43,239** legacy simulation assertions.
- **24,955** tactical assertions covering six deterministic flight styles, gust warning timing, configuration bounds/reset, telegraphed attacks, leverage, tension and exploit defenses.
- **72** existing complete seeded matches.
- **252** campaign/exploit matches with **967** assertions. The simple fixed-height pull/ease bot wins 10 of the 12 authored stages and loses both champion finales. A height/gust-aware bot wins all 12; every stage's medal goals are attainable. These bots use visible simulation state. This establishes rule consistency and attainable goals, not human difficulty or enjoyment.
- **14** existing profile persistence/corruption checks.
- **152** campaign/profile checks: old-save migration, unlock order, medal bests, no repeated awards, cosmetic gates, tournament win/loss/draw/final, save/resume and invalid/future/corrupt save protection.
- **52** optional-service coordinator/bridge checks. Guest play, age/consent/test opt-in gates, unavailable services, cancellation, timeout and duplicate/stale callbacks remain covered.
- **32** existing scene/input/navigation checks.
- **423** new scene/input/layout checks: campaign retry/next, cup advance/resume/elimination/title, duplicate result protection, practice completion/restart/no rewards, guest service gates, hit regions, five viewport geometries and text extents for chapter lists/briefings/buttons. The last practice header change was rechecked.
- **8** fake-native wiring fixture checks. These are not real Google SDK sessions.
- A final **180-frame headless startup** without script errors or warnings.

This summarizes checks on the original campaign source. Generated logs are excluded from the source repository; rerun the commands below for your local build. Headless checks use dummy rendering. Font metrics and hit rectangles do not establish that a real phone's rendered screen looks good.

## Android verification

The final APK is exported with the existing licensed official Platform36 / Build-Tools36.1 and full Gradle runtime dependencies, then checked for package/version/API levels, ARM64 libraries, debug signature, 16KiB ZIP/native alignment, native SDK classes, test-only configuration and minimized permissions. Generated APKs, signing information and machine-specific build logs are excluded from this source repository.

The original native plugin AAR is unchanged from 0.9.1:
`52abd000e3d4a1c0864e86f761acdf85990eba2f63b3fe0d2beafcfa7a0ff14a`

The package remains `org.rooftoprivals.prototype`, with version code4 and version name `0.10.0-campaign-preview`. The same development certificate is retained. **An actual Android install/update was not performed.**

## Explicitly unverified or not implemented

- Physical Android execution, actual multi-touch/cutouts, background/resume behavior, audio/haptics, visual composition, frame-time, battery/thermal performance or phone compatibility.
- Actual Google sign-in, UMP regional consent completion, test-ad display/completion or network inspection. Missing OAuth client configuration leaves sign-in unavailable. Sample AdMob configuration may fail UMP; such errors block the request.
- Production auth, cloud saves, online/multiplayer, secure rewards or anti-cheat.
- Separate city geometry: four chapters currently share the procedural arena with different lighting and rival palettes.
- A Play release, live ads, production signing, release AAB, store policy approval, audience declarations, privacy/data-safety completion or monetization readiness.

Rendered visual testing and real-phone playtesting remain required; headless tests do not establish visual quality or device compatibility.

## Repeat checks

With Godot4.6.3, run each from the source root:

```bash
for test in test_battle test_tactics test_match test_campaign_battles test_profile test_campaign test_services test_scene test_campaign_scene test_native_wiring; do
  godot --headless --path godot --script res://tests/$test.gd || exit 1
done
godot --headless --path godot --quit-after 180
```

Same-process determinism is not a cross-platform multiplayer lockstep guarantee.
