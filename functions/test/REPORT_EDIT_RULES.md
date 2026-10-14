# Local report editing checks

These tests use fictional users and the project ID `demo-micomunidad-report-edit`. They never use service account credentials or a live Firebase project. The REST test client only accepts a `127.0.0.1` emulator host. Its unsigned tokens are test-only tokens accepted by the emulator, not real authentication credentials.

Each run clears only the in-memory database of that fixed demo project in the loopback emulator before seeding fixtures, making reruns independent. Do not use this demo emulator database to store data you want to keep.

From the Flutter project folder:

```powershell
flutter test --dart-define-from-file=config/community.example.json
```

For the actual Firestore rule tests, start the official Firestore emulator with Java 21. Supply the path to your locally downloaded official emulator JAR:

```powershell
java -jar "PATH_TO_FIRESTORE_EMULATOR.jar" --host 127.0.0.1 --port 8088 --project_id demo-micomunidad-report-edit --rules firestore.rules --single_project_mode --single_project_mode_error
```

In a second terminal, from the same project folder:

```powershell
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8088"
node --test functions/test/report_edit.rules.test.cjs
Remove-Item Env:FIRESTORE_EMULATOR_HOST
```

Stop the emulator with Ctrl+C when finished. No emulator data is exported. Without `FIRESTORE_EMULATOR_HOST`, this rules suite is skipped; that is not a successful security validation. The Flutter tests use in-memory Firestore data, and do not replace the emulator rules tests.

Coverage includes: own pending and approved active reports, different authors, unapproved/anonymous users, completed/rejected reports, protected fields, invalid values, limits, server timestamps, and preservation of existing administrator moderation.

Administrator content editing requires authorship. It covers active reports and, by explicit authorization, approved resolved reports authored by that same approved administrator. Residents still cannot edit resolved content; no author can edit rejected content. Administrator status and moderation updates are separate whitelisted operations and cannot include content or ownership changes. Tests cover both authors, approved-only operational status updates, rejection/approval with server timestamps, mixed-action rejection, and the ability to resolve, edit one's own resolved content, and reopen through the status action. Photo/comment creation permissions in History do not change.

Only the local `firestore.rules` file is loaded. Running these tests does not deploy rules. Production editing needs a separately authorized deployment of the reviewed rules and the updated Flutter application.

Approved users may create comments on approved active or resolved reports, but not pending/rejected or missing reports. Resolved photo uploads remain blocked. Before permanent deletion the administrator transactionally marks the completed parent `deletionInProgress: true`; comments and parent edits/status changes are then blocked. The marker is retained on failure for safe retries, and parent deletion requires it. Tests cover late comments before/after the deletion marker and parent removal, plus role/ownership/length checks. Update the Flutter application before attempting deletion with these rules; older clients do not set the required marker.
