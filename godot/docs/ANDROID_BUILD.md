# Build the Android SDK test preview

This source corresponds to **0.10.0-campaign-preview / version code 4**, package `org.rooftoprivals.prototype`, ARM64, Android 7/API 24 minimum and target API 36. It is a debug test build, not a store-ready or privacy-certified release. This repository is a source-only snapshot of the latest campaign preview.

## Setup on your build computer

1. Install Godot 4.6.3 and its matching official export templates.
2. Install Java 17 or a compatible newer JDK and Android SDK Platform 36 / Build-Tools 36.1.0. Review and accept required SDK terms yourself. Configure Java SDK, Android SDK and your own debug keystore in Godot Editor Settings > Export > Android. This bundle contains no SDK path, credentials, or signing key.
3. Open `godot/project.godot`. Use Project > Install Android Build Template.
4. From this source bundle's root, run `python3 tools/configure_android_template.py`. This updates the generated template to AGP 8.9.2 with Gradle 8.11.1, preserves already-built Godot native libraries (no NDK stripping), and disables automatic SDK package downloads. The official template supplies the Gradle wrapper and Godot AAR.
5. Build the native plugin from source (Python 3 and JDK 17+ required):

   ```bash
   cd android-services
   python3 fetch_compile_deps.py
   ./build_thin_aar.sh
   python3 test_contract.py
   cd ..
   cp android-services/build/kite-google-services.aar godot/android/plugins/
   ```

   The fetcher downloads pinned compile dependencies from official Google Maven and Maven Central. No prebuilt AAR or dependencies are tracked. The `.gdap` dependency pins are included in `godot/android/plugins/`. Android export uses the Gradle build and enables the plugin.
6. Run `tools/export_android_debug.sh` or export the Android preset from Godot. Output: `godot/build/rooftop-rivals-campaign-preview.apk`.

The build must resolve official Google Maven/Maven Central dependencies. Pins: Google Mobile Ads 25.5.0, UMP 4.0.0, Credential Manager 1.6.0, GoogleID 1.2.1. The thin plugin AAR contains only plugin code; Gradle adds actual runtime SDKs. To rebuild plugin source, see `android-services/README.md` at bundle root, then copy its rebuilt AAR to `godot/android/plugins/`.

## Account and test-ad configuration

Only Google's official sample AdMob app/unit IDs are included. Ads are optional TEST ads and do not grant production rewards. Google sign-in SDK code is present, but operational sign-in requires your legitimate OAuth Android client registration and matching public web/server client ID. No OAuth account/client was registered and no sign-in was performed for this build.

The optional `godot/config/google_sign_in.json` uses `{"server_client_id":""}`. It must contain only a public web client ID, never a client secret. The export include filter preserves this file if provided. The bundled .example.json file is not loaded; no configured client ID is shipped, leaving login unavailable and guest play working. A successful client callback is not backend account authentication; server verification/session implementation remains a production gate.

## Verification and caveats

The original campaign preview passed export, manifest, signature, alignment and dependency checks. Generated verification logs, artifacts and machine-specific paths are deliberately excluded from this source repository. `VALIDATION.md` summarizes the scope and repeatable game checks. No physical device/emulator installation or real provider flow was tested. Test cancellation, background/resume, network loss, UMP, ad playback and Google credential UI on actual devices before release. Runtime behavior of the minimized manifest, including explicit Mobile Ads initialization after consent, remains unverified.

The APK uses the existing temporary debug certificate and package ID so it can update the earlier preview. The previous preview certificate and signing key are not distributed in this repository. Rebuilding with a different local debug key cannot update that APK in place; Android would require uninstalling the old app, which can erase local progress. The signing key is deliberately not in this bundle.

Native libraries remain uncompressed under the official Gradle preset; this makes the APK larger than the legacy prebuilt-template export. No shrinker/minifier or native optimization was introduced. The build is not suitable for Play Store publication. Production requires owner-controlled signing, approved provider configuration, backend verification, privacy/data disclosures, device QA, store compliance review and a release AAB.
