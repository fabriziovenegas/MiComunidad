# Profile updates and request lookup

The profile contains the current name, national identity number (DNI), phone,
email, address, time in the community and reason for joining. The updated app
sends all seven fields to `updateOwnProfile` in one request. The backend validates
them and commits the profile and its lookup information together in Firestore.

## Original application versus current information

The original fields in `accessRequests` remain unchanged: they describe what was
submitted when applying. This is not a new History screen or a full version log.

For the most recent approved request linked to the account, the server maintains:

- `approvedUserId`: the stable account UID, not the DNI.
- `lookupDni`: the current DNI used to find the request.
- `currentProfile`: a snapshot of the seven current fields, used after withdrawal.
- `profileUpdatedAt`: when this snapshot was updated.

The public lookup still returns only the name, masked email, status, rejection
reason and original application date. It does not return the phone, address,
profile snapshot, document link or UID. This change does not add identity
verification to the existing DNI lookup.

A linked approved account with its current DNI takes precedence over a newer
rejected or pending duplicate. Other cases retain the latest-application behavior.
New requests are saved atomically through a server callable; see
[access requests and duplicate protection](ACCESS_REQUESTS.md).

After a correction, the former DNI no longer locates that same account. It may
still locate an independent application for another person. Pending and rejected
applications use their originally submitted DNI and contact information.

Withdrawing a member stores the latest snapshot before deleting the profile.
The server first marks `profileWithdrawalInProgress` to freeze further profile
corrections while withdrawing access. If a later step fails, the profile stays
locked until an administrator retries withdrawal.
The latest DNI can therefore still show the withdrawn status. A later application
is independent and does not overwrite the earlier application.

## Duplicate checks and failures

The backend rejects a DNI used by another account or a pending application.
Server-only `memberDniKeys` documents also prevent concurrent approvals and
profile corrections from assigning the same DNI to two accounts. These keys use
hashed document IDs; hashing is not a substitute for access control. The existing
default-deny Firestore rule blocks client access. Keys are released after a DNI
correction or completed withdrawal.

Pending applications also reserve this document, storing their anonymous
`userId` and `requestId`. Approval replaces that reservation with the approved
account's `userId`. Older rejected, withdrawn or deleted applications do not
permanently hold a reservation.

Authentication is a separate service and cannot join a Firestore transaction.
Name/email changes first update Authentication. If the Firestore commit fails,
the backend attempts to restore Authentication from the stored profile and reports
failure. If that restoration also fails, an explicit retry is required; this is
not a distributed transaction across both services.

No bulk migration is included. Existing requests with `approvedUserId` can use
the current profile even if the DNI was corrected before this update. Legacy
approvals without that link are associated only when the stored DNI identifies
one account and any available emails agree. Ambiguous old records require an
administrator's review; they are not relinked by guessing. Deleted applications
are not recreated.

Older app versions can still send the four identity/contact fields; omitted
community fields are preserved. Use the updated app to save all seven fields in
one backend operation. Existing reports, comments, projects and account roles
are not rewritten.

## Deployment and local checks

The updated backend handlers are `updateOwnProfile`, `getAccessRequestStatus`,
`reviewAccessRequest` and `removeNeighbor`, with their shared module
`functions/profile_identity.js`. No rule or composite-index change is required.
Deploy these handlers only to your own selected Firebase project, after review.
Deployment does not migrate existing documents or run the tests against live data.

Run the Flutter tests with the public configuration:

```powershell
flutter test --dart-define-from-file=config/community.example.json
```

Run unit checks without Firebase:

```powershell
node --test functions/test/profile_identity.test.cjs functions/test/member_removal.test.cjs functions/test/privacy.test.cjs
```

For `profile_identity.emulator.test.cjs`, start local Firestore and Authentication
emulators first. Set `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` to
their respective `127.0.0.1:PORT` addresses and run the file with `node --test`.
That suite uses the fixed project `demo-micomunidad-profile-identity` and resets
only that local demo database and its demo Authentication users. It does not use
administrative credentials or contact live Firebase. Without both emulator
variables, it skips rather than validating integration.
