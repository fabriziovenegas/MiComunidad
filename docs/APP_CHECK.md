# Firebase App Check

The App Check integration is prepared but **disabled by default**. It makes no console, enforcement or credential changes automatically. Enable it only after configuring your own Firebase registration by supplying `ENABLE_FIREBASE_APP_CHECK=true` at build time.

When enabled, Android builds install an App Check provider after Firebase initialization and before application requests. Debug builds use the debug provider. Profile and release builds use Play Integrity; they never select the debug provider.

## Local development

Register your development token in your own Firebase project under **App Check → Apps → Manage debug tokens**. The Android SDK can generate a token for each test device and print it in the local debug log. Alternatively, supply a private token using `FIREBASE_APP_CHECK_DEBUG_TOKEN` and `ENABLE_FIREBASE_APP_CHECK=true` in an ignored `config/app-check.local.json` file and pass `--dart-define-from-file=config/app-check.local.json` when launching a debug build. Never reuse another project's token. Until configured and enabled, the original "No AppCheckProvider installed" warning may still appear.

Keep the token and debug APK private. Never add the local file to Git, publish it in screenshots/logs, or distribute debug APKs to users. Public source includes no registered token or production Firebase configuration. An unconfigured public build still opens the Firebase configuration message.

## APK distribution

Before making App Check mandatory, configure Play Integrity for your own Android registration and final signing certificate. Check its settings for your distribution method, including installations outside Google Play. Test a signed release APK on physical devices and review App Check metrics before enabling enforcement.

Installing the provider does not change Firebase enforcement, access rules or permissions. Authentication and Security Rules still apply. Provider initialization does not wait for a network token and has a bounded local initialization wait so loss of connectivity cannot hold startup indefinitely.

Official guides: [Flutter setup](https://firebase.google.com/docs/app-check/flutter/default-providers), [debug devices](https://firebase.google.com/docs/app-check/flutter/debug-provider), [Android Play Integrity](https://firebase.google.com/docs/app-check/android/play-integrity-provider).
