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

The steps below focus on Android and Windows PowerShell. Replace every `YOUR_...` value with information from **your own Firebase project**. Setup and deployment commands affect that project, so check its ID before running them.

### A. Create your project and enable its services

1. Create a new project in the [Firebase console](https://console.firebase.google.com/). Note its **project ID**, which is different from its display name.
2. Review the [Blaze plan requirements](https://firebase.google.com/docs/functions/get-started) and costs before enabling billing. Deployed Cloud Functions and current Cloud Storage setup require this plan. A budget alert helps monitor spending but does not cap it.
3. In **Authentication → Sign-in method**, enable **Email/Password** and **Anonymous**. Listing providers in `firebase.json` does not enable them in the live project.
4. Create a **Cloud Firestore** database in **Native mode**, with database ID **`(default)`**. Start with restricted rules rather than public test-mode access.
5. Create the default **Storage** bucket with restricted rules. Use its exact name from the console, whether it ends in `.firebasestorage.app` or `.appspot.com`.
6. Register an **Android app** with package name **`com.example.trabajo_app.demo`** for the `demo` build. If you also build `private`, register **`com.example.trabajo_app`** separately. Each registration has its own app ID.

The included Functions and Flutter client both use `southamerica-east1`. Keep that Functions region unless you update both sides. Firestore and Storage have separate location choices; review them before creating those resources.

### B. Add your app connection settings locally

From the folder containing `pubspec.yaml`, create local copies if they do not already exist:

```powershell
if (!(Test-Path config/community.local.json)) {
    Copy-Item config/community.example.json config/community.local.json
}
if (!(Test-Path config/firebase.local.json)) {
    Copy-Item config/firebase.example.json config/firebase.local.json
}
```

Edit `config/firebase.local.json` with your own Android registration values. The downloaded `google-services.json` contains these values:

| Field in the `android` example | Value from your registration |
|---|---|
| `apiKey` | The matching client's `api_key[].current_key`. |
| `appId` | The matching client's `client_info.mobilesdk_app_id`. |
| `messagingSenderId` | `project_info.project_number`, as a string. |
| `projectId` | `project_info.project_id`. |
| `storageBucket` | `project_info.storage_bucket`. |

Choose the client whose `android_client_info.package_name` matches the build you will run. Fill the other platform sections only if you plan to use them; their placeholders are not working Firebase registrations.

Save those settings inside `FIREBASE_OPTIONS` using this PowerShell block. It updates only the local configuration and does not print its values:

```powershell
$communitySettings = Get-Content config/community.local.json -Raw | ConvertFrom-Json
$firebaseSettings = Get-Content config/firebase.local.json -Raw | ConvertFrom-Json
$communitySettings.FIREBASE_OPTIONS = $firebaseSettings | ConvertTo-Json -Depth 20 -Compress
$settingsPath = (Resolve-Path config/community.local.json).Path
[System.IO.File]::WriteAllText(
    $settingsPath,
    ($communitySettings | ConvertTo-Json -Depth 30),
    [System.Text.UTF8Encoding]::new($false)
)
```

You may also save your own `android/app/google-services.json`. The Google Services plugin runs only when Firebase build settings are present and the project in that file matches them. Its client registration must also match the Android package name. Explicit Dart settings can be used without this file.

These local JSON files and native Firebase registration files are ignored by Git. Never use a service account key as `FIREBASE_OPTIONS`.

### C. Install the tools and confirm your target

Install **Node.js 22**, Flutter with an Android SDK, and the Firebase CLI. Run these commands in PowerShell from the Flutter project folder:

```powershell
npm install -g firebase-tools
firebase login
firebase projects:list
$setupProjectId = "YOUR_PROJECT_ID"
firebase apps:list --project $setupProjectId
npm --prefix functions ci
```

Complete Google sign-in yourself in the browser. If browser redirection does not work, use `firebase login --no-localhost`. Check the project ID and registered Android package before proceeding. Every deployment command below includes `--project` so its target is explicit.

The repository already includes `firebase.json`, rules and indexes. You do not need to run `firebase init` or replace those files. If you choose to create a local project alias with `firebase use --add`, keep `.firebaserc` out of Git.

### D. Configure server settings and email

Functions use `COMMUNITY_NAME` and `COMMUNITY_ID`, with the neutral defaults `MiComunidad` and `community`. You may keep those defaults for testing. To change them for your own deployment, create the ignored file `functions/.env.YOUR_PROJECT_ID`, replacing `YOUR_PROJECT_ID` in its filename:

```dotenv
COMMUNITY_NAME="MiComunidad"
COMMUNITY_ID="community"
```

Keep the first administrator's `communityId` consistent with this setting. `functions/.env.local` is for emulator overrides rather than a live deployment.

The code declares two email secrets. Create them in your own project's Secret Manager before deploying Functions:

```powershell
firebase functions:secrets:set GMAIL_USER --project $setupProjectId
firebase functions:secrets:set GMAIL_PASSWORD --project $setupProjectId
```

Enter values only at the CLI prompts. For the Gmail transport used here, use your sending account and its supported app password. Review [Google's app password requirements](https://support.google.com/accounts/answer/185833). Never put these values in an `.env` file, the README or the app's build settings. Changing a secret requires redeploying the Functions that use it.

Deploying all included Functions requires these two declared secrets even if you do not use code-based password recovery. If you do not want to configure Gmail, review which Functions to deploy in your own installation rather than entering invented email credentials.

The normal **Forgot password** screen uses Firebase Authentication's own reset emails. The separate code-based reset function binds the two Gmail secrets. **Approval/rejection emails need an additional backend adjustment:** `reviewAccessRequest` currently does not bind those secrets. Setting the secrets alone will not enable its notifications. Until that is adjusted, an approved user can use **Forgot password** to set a password through Firebase Authentication. Do not place passwords or email secrets in an access request.

### E. Deploy the included backend to your project

Run from the Flutter project folder after checking `$setupProjectId`:

```powershell
firebase deploy --only "firestore:rules,firestore:indexes" --project $setupProjectId
firebase deploy --only functions --project $setupProjectId
firebase deploy --only storage --project $setupProjectId
```

These commands deploy Firestore rules/indexes, Functions and Storage rules. They do not deploy Hosting. Functions deployment may ask to enable its required Google Cloud APIs and service permissions in your project. Review the prompts and costs. Wait until each command reports success and Firestore indexes finish building.

Storage rules use `firestore.get()` and `firestore.exists()` to check the parent project or report. The first Storage rules deployment may ask to enable cross-service access. For that specific access, check that the requested role is **Firebase Rules Firestore Service Agent** (`roles/firebaserules.firestoreServiceAgent`) on your project's Storage service agent:

```text
service-YOUR_PROJECT_NUMBER@gcp-sa-firebasestorage.iam.gserviceaccount.com
```

`YOUR_PROJECT_NUMBER` is the numeric project number, not the project ID. The CLI can grant the required role after you approve the prompt. If you cannot approve it, ask your project's IAM administrator to grant this specific role to that service agent. Do not grant it to residents or make the bucket public. See [Firebase's cross-service rules instructions](https://firebase.google.com/docs/rules/manage-deploy#manage_permissions_for_cross-service_cloud_storage_security_rules).

### F. Create the first administrator

The app cannot approve its first administrator by itself. A project owner must create this account once, in their own Firebase project. Later administrators can be managed through the app's existing member controls.

1. In **Authentication → Users**, add an Email/Password user. Choose your own email and a strong password. Copy its **UID**.
2. In Firestore, create **`users/{UID}`**, using that exact UID as the document ID. The table below shows the profile fields used by the app. Example profile information is fictional; enter your own appropriate information privately.

| Field | Type | Initial value |
|---|---|---|
| `userId` | String | The Authentication UID. |
| `email` | String | The same email as the Authentication account. |
| `nombre` | String | `Demo Administrator`. |
| `role` | String | `admin`. |
| `approvalStatus` | String | `aprobado`. |
| `communityId` | String | `community`, or your server's `COMMUNITY_ID`. |
| `dni` | String | `00000000` for isolated testing. |
| `phone` | String | `000000000` for isolated testing. |
| `address` | String | `Demo address`. |
| `timeLivingHere` | String | `Demo`. |
| `reason` | String | `Initial setup for testing`. |
| `joinDate`, `createdAt`, `updatedAt` | Timestamp | The current date and time, entered as Timestamp fields. |

3. Set that account's **custom claims** to `approved: true` and `role: "admin"` with the Firebase Admin SDK. Firestore checks the profile; Storage checks these claims. Both must be present. The Authentication console does not provide a custom-claims editor.

For a local setup, follow the [Admin SDK credential instructions](https://firebase.google.com/docs/admin/setup) for **your own project**. Keep the downloaded administrative credential outside this repository, on a trusted computer. If your organization forbids service account keys, use an approved privileged environment instead.

The following PowerShell example only sets claims on an account that already exists. Replace the path, project ID and UID before running it. It checks that the credential belongs to the selected project and preserves other existing claims. Run it from the Flutter project folder after installing the Functions dependencies:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\PrivateFirebase\YOUR_OWN_PROJECT-service-account.json"
$env:MICOMUNIDAD_SETUP_PROJECT = "YOUR_PROJECT_ID"
$env:MICOMUNIDAD_ADMIN_UID = "UID_FROM_AUTHENTICATION"
Push-Location functions
@'
const fs = require("node:fs");
const {initializeApp, cert} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");

async function setFirstAdminClaims() {
  const projectId = process.env.MICOMUNIDAD_SETUP_PROJECT;
  const uid = process.env.MICOMUNIDAD_ADMIN_UID;
  if (!projectId || projectId.startsWith("YOUR_") ||
      !uid || uid === "UID_FROM_AUTHENTICATION") {
    throw new Error("Replace the project ID and UID placeholders first.");
  }
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error("Close the emulator setup before setting live claims.");
  }
  const key = JSON.parse(fs.readFileSync(
      process.env.GOOGLE_APPLICATION_CREDENTIALS, "utf8"));
  if (key.project_id !== projectId) {
    throw new Error("The credential belongs to a different project.");
  }
  initializeApp({credential: cert(key), projectId});
  const auth = getAuth();
  const account = await auth.getUser(uid);
  await auth.setCustomUserClaims(uid, {
    ...account.customClaims, approved: true, role: "admin",
  });
  console.log("Administrator claims saved. Sign out and sign in again.");
}

setFirstAdminClaims().catch(() => {
  console.error("Setup failed. Check the project ID, UID and credential permissions.");
  process.exitCode = 1;
});
'@ | node
Pop-Location
Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS
Remove-Item Env:MICOMUNIDAD_SETUP_PROJECT
Remove-Item Env:MICOMUNIDAD_ADMIN_UID
```

This is a one-time privileged setup command, not code to add to Flutter or deploy as a public Function. It does not create the profile or change a password. Protect the credential and revoke a temporary key when it is no longer needed. Sign out and sign in again after assigning claims so the app receives a new token. See [Firebase's custom claims documentation](https://firebase.google.com/docs/auth/admin/custom-claims).

### G. Open the connected app and check the setup

You can connect the `demo` flavor to your own Firebase while keeping the generic logo and example map:

```powershell
flutter run --flavor demo --dart-define-from-file=config/community.local.json
```

Sign in with the administrator account you created. Projects, reports and requests are initially empty; the repository does not import data or create sample residents. Create fictional projects and reports through the app when testing. A resident needs an approved profile and appropriate claims before using the internal features.

| Message or behavior | What to check |
|---|---|
| “Firebase no configurado” | `FIREBASE_OPTIONS` is not empty, contains valid JSON and has the current platform's settings. |
| Sign-in is blocked | Email/Password is enabled, and `users/{UID}` exists with `role: admin` and `approvalStatus: aprobado`. |
| Firestore denies access | The rules were deployed to the same project as the app, and the signed-in profile is approved. |
| Storage denies access | The account has fresh `approved`/`role` claims; the cross-service role is enabled; and the parent record allows the action. |
| Request lookup or moderation cannot connect | Functions are deployed in `southamerica-east1` in the app's project. |
| A query needs an index | The included indexes are deployed and ready. If Firebase requests another index, review it for your own project. |
| Approval email does not arrive | Review the notification limitation in step D; creating secrets alone does not fix the missing binding. |
| Report edits cannot be saved | Use the updated app and matching Firestore rules in the same project. Residents may edit their own active reports; approved administrators may also edit their own resolved reports. Reports being deleted are locked. |

For isolated testing, start Firebase emulators with `firebase emulators:start --project YOUR_PROJECT_ID`. Run Flutter with `--dart-define=USE_FIREBASE_EMULATORS=true`, a matching local Firebase configuration, and your chosen flavor. The connection helper uses `10.0.2.2` on Android emulators and `127.0.0.1` on desktop/web; a physical Android phone needs a different reachable host. Emulator data and accounts are separate, so the live administrator account does not automatically exist there. Do not run tests against a real community database.

Further details: [Functions environment settings and secrets](https://firebase.google.com/docs/functions/config-env) and [Storage billing requirements](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024).

### Report permissions and updates

- Approved residents can edit their own active reports.
- Approved administrators can edit their own reports, including approved reports marked **Resolved**. For reports submitted by someone else, the administrator opens only the status selector.
- Approved residents and administrators can comment on approved active or resolved reports. Rejected reports do not accept new comments or content edits.
- Resolved reports do not accept new photographs; existing files remain read-only in that view.
- Before permanent deletion, the app marks the completed report `deletionInProgress: true`. This blocks new comments and changes to the report while its files, photo records and comments are removed. The main record is removed last.
- If deletion fails, the main record remains locked so an administrator can retry safely. Do not manually clear the marker while dependencies may still be pending.

Use the updated app and matching Firestore rules together. Older app versions do not set the deletion marker and cannot complete permanent deletion with these rules. No bulk data migration is required: the marker is added only when an administrator starts deletion.

For local checks using fictional data and a Firestore emulator, see [report checks](../functions/test/REPORT_EDIT_RULES.md). These tests do not deploy rules or access a live database.

## 4. Run or build a private version

After adding your own Firebase settings and the required private images:

```powershell
flutter run --flavor private --dart-define-from-file=config/community.local.json
flutter build apk --release --flavor private --dart-define-from-file=config/community.local.json
```

The two Android versions package images differently:

- **`demo`** is the default. It includes the app’s branding but leaves out private community photographs, even if they are on your computer.
- **`private`** includes the welcome image and three community photographs stored locally and ignored by Git. All four files must exist before building this version; missing images are not silently replaced.

For `private`, supply your own authorized images at these paths: `assets/images/Imagen_de_Inicio.png`, `assets/images/community/community_view.png`, `assets/images/community/community_families.png` and `assets/images/community/community_work.png`. Use the Firebase registration for `com.example.trabajo_app`, rather than the `.demo` registration. The `demo` flavor does not require those files; static analysis may still report four missing-private-asset warnings in a clean checkout.

The private version keeps the original Android app identifier. The demo adds `.demo`, so installing it does not replace the private app. This separation is configured for Android; other platforms need their own setup before using private photographs.

A private APK may show your real location, community history and photographs. Do not share it as a public demo.

## 5. Before sharing or releasing

- **Keep secrets out of the app.** Build settings become part of the APK or web app and can be extracted. Never include passwords, private keys, service account credentials or administrator tokens.
- **Check what you publish.** Do not upload local settings, database exports, personal documents, real community photographs, Git backups or private builds.
- **Use fictional data for public screenshots.** Once connected, the app displays information from your Firebase project. Do not expose real community data or present sample counts as actual adoption or impact.
- **Review the request-status lookup.** Looking up an access request by DNI (national identity number) has privacy risks. Hiding part of an email address does not prove who is making the request or protect other returned details, such as a name, status or reason. Review access and abuse protection before real-world use.
- **Prepare your Android signing key.** The release build currently uses a test signing setup. Configure your own private signing key before distributing through an app store.
- **Review Firebase separately.** Choosing a public or private build does not change deployed Firebase rules, permissions or services.
