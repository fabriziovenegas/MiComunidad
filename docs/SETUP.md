# Setup Guide

This guide explains how to build MiComunidad and connect it to your own Firebase project.

The shared code does not include the real community’s names, map, history, photographs or Firebase settings. The example data is fictional and does not represent real users or activity.

## 1. Build the public example

Run these commands from the Flutter project folder: the folder containing `pubspec.yaml`.

```powershell
flutter pub get
flutter test --dart-define-from-file=config/community.example.json
flutter build apk --flavor demo --dart-define-from-file=config/community.example.json
```

The app reads its settings from `config/community.example.json` when it is built. It does not load an `.env` file as an app asset.

The example leaves `FIREBASE_OPTIONS` empty. You can build and open the app, but it will show **“Firebase no configurado” (“Firebase not configured”)** instead of opening its internal screens. It does not automatically provide sample reports, projects or members.

## 2. Add your own settings

Copy `config/community.example.json` to `config/community.local.json` and edit the copy. Git is configured to ignore this local file so that your settings stay out of the repository.

| Setting | What it controls |
|---|---|
| `APP_NAME`, `COMMUNITY_NAME`, `SHORT_NAME` | Names displayed in the app. |
| `COMMUNITY_LEGAL_NAME` | Community name shown in its information page. |
| `ANNIVERSARY_TITLE`, `ANNIVERSARY_DATES` | Text displayed in the anniversary banner. |
| `COMMUNITY_HISTORY` | Paragraphs about the community. |
| `COMMUNITY_MAP` | Map location, boundary and reference points. |
| `FIREBASE_OPTIONS` | Your Firebase connection settings for each platform. Leave this empty to keep Firebase disabled. |

The last three settings contain structured information saved as a single text value. Follow the format in the example file. If you prepare that information separately as JSON, `JSON.stringify(...)` or `ConvertTo-Json -Compress` can turn it into the text value needed by the settings file.

### Map settings

The example map is in the ocean and does not identify homes or people. To use your own map, keep these fields:

- `reference` and `center`: coordinates written as `[latitude, longitude]`.
- `bounds`: two coordinate pairs defining the map’s viewing area.
- `boundary`: a list of coordinates outlining the community.
- `url`: the map link.
- `landmarks`: reference points, each with a `name`, `description`, `point` and `icon`.

Available icon names are `transport`, `religion`, `community`, `shop`, `sports` and `bank`.

If the settings file has a formatting error, correct that file rather than placing private information directly in the app’s source code.

## 3. Connect your own Firebase project

Firebase provides sign-in, shared data and file storage. To use the app’s connected features:

1. Create your own Firebase project and register the platforms you plan to use, with their correct app identifiers. You do not need access to the original community’s project.
2. Use `config/firebase.example.json` as a template for your project’s app connection settings. Save those settings as a text value in `FIREBASE_OPTIONS` in your local configuration file.
3. For Android, you may also add your own `android/app/google-services.json`. Git ignores this file. The Google Services plugin is used only when Firebase build settings are present and the project in this file matches them. The app can also use the explicit Dart settings without this Android file.
4. Set up Authentication with email and anonymous sign-in, Cloud Firestore, Storage and the Cloud Functions used by the app. Review the included access rules, including the permissions needed for Storage rules to check Firestore records. Downloading the code does not set up or deploy these services for you.
5. Select your own Firebase project locally. Do not upload `.firebaserc`. Any setup or deployment affects the Firebase project you select.

### Settings for Cloud Functions

Cloud Functions use `COMMUNITY_NAME` and `COMMUNITY_ID` as server settings, with neutral defaults. The file `functions/.env.local` is only for Firebase emulators. For your own deployment, configure these settings through the Firebase CLI workflow.

If you use email features, keep `GMAIL_USER` and `GMAIL_PASSWORD` in the backend’s secret storage. Never include them in the app’s build settings.

For isolated testing, use Firebase emulators with `--dart-define=USE_FIREBASE_EMULATORS=true`. Do not run tests against a real community database.

## 4. Run or build a private version

After adding your own Firebase settings and the required private images:

```powershell
flutter run --flavor private --dart-define-from-file=config/community.local.json
flutter build apk --release --flavor private --dart-define-from-file=config/community.local.json
```

The two Android versions package images differently:

- **`demo`** is the default. It includes the app’s branding but leaves out private community photographs, even if they are on your computer.
- **`private`** includes the welcome image and three community photographs stored locally and ignored by Git. All four files must exist before building this version; missing images are not silently replaced.

The private version keeps the original Android app identifier. The demo adds `.demo`, so installing it does not replace the private app. This separation is configured for Android; other platforms need their own setup before using private photographs.

A private APK may show your real location, community history and photographs. Do not share it as a public demo.

## 5. Before sharing or releasing

- **Keep secrets out of the app.** Build settings become part of the APK or web app and can be extracted. Never include passwords, private keys, service account credentials or administrator tokens.
- **Check what you publish.** Do not upload local settings, database exports, personal documents, real community photographs, Git backups or private builds.
- **Use fictional data for public screenshots.** Once connected, the app displays information from your Firebase project. Do not expose real community data or present sample counts as actual adoption or impact.
- **Review the request-status lookup.** Looking up an access request by DNI (national identity number) has privacy risks. Hiding part of an email address does not prove who is making the request or protect other returned details, such as a name, status or reason. Review access and abuse protection before real-world use.
- **Prepare your Android signing key.** The release build currently uses a test signing setup. Configure your own private signing key before distributing through an app store.
- **Review Firebase separately.** Choosing a public or private build does not change deployed Firebase rules, permissions or services.
