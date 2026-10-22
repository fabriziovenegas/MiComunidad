# Access requests and duplicate DNI/email protection

Access requests are saved through the `submitAccessRequest` callable, using an
anonymous Firebase Authentication session. The existing form and document upload
remain in place. The server validates the applicant's attachment in its own
Storage bucket, derives its download URL, validates the submitted fields and
saves the pending request in a Firestore transaction.

## One active request per DNI

The transaction reads and writes the server-only `memberDniKeys` document for the
DNI. Concurrent submissions cannot both claim it. The same document is used by
approvals and profile corrections, so these operations also participate in the
conflict check. A pending reservation contains the anonymous `userId` and the
`requestId`; approval replaces it with the approved account's `userId`.

Existing members and older pending requests without a reservation are checked
as well. Rejected, withdrawn or deleted requests do not reserve the DNI forever.
The server accepts a retry with the same request identifier and identical data
without creating a second request. It never overwrites an existing request with
different data or a different applicant.

Firestore rules deny direct client creation of `accessRequests`. Client-side
checks alone cannot prevent simultaneous requests or protect against an older
client bypassing the callable. The DNI reservation collection remains inaccessible
to clients under the existing default-deny rule.

## One active request or account per email

Email addresses are trimmed and lowercased. Pending requests reserve a server-only
`memberEmailKeys` document in the same transaction as the DNI and application.
Different DNIs cannot submit the same email concurrently. Existing pending
requests without keys (including mixed-case addresses) and current Authentication
accounts are checked too. Read failures do not silently bypass these checks.

Approvals and profile corrections use the same email key. Correcting a profile
releases its former email after committing the new one; withdrawing a member
releases the key after the existing account-removal workflow. Rejected or withdrawn
historical applications do not reserve an email, but another pending application
or existing account still blocks reuse. Original applications are never rewritten.
No Gmail-specific alias rewriting is performed (dots and plus-addresses stay as entered).
Each account requires its own email address.

Older duplicate pending requests require administrative review; they are not
automatically rejected or deleted. The pending-email check reads pending requests
to cover legacy case variants without a migration; its read cost grows with that
queue. New hashed email keys remain protected by the existing default-deny rule.

## Request lookup and history

A request linked to an existing approved account with the current DNI takes
precedence over a newer rejected or pending duplicate. Otherwise, the most recent
matching application remains the result, as before. Lookup does not invent an
application when none exists, and does not relink ambiguous historical records.
The existing masked-email response and returned fields remain unchanged.

Original application fields are preserved. Profile corrections still update the
current lookup DNI; withdrawal preserves its latest snapshot. Reports, projects,
comments, roles and account identifiers are not rewritten by this correction.

No bulk migration, automatic rejection or deletion of old requests is performed.
If an administrator finds older duplicate pending requests, they must review
them and reject the duplicate before approving the valid one. Files uploaded
before a failed submission are not automatically deleted: an uncertain network
response must not cause deletion of a document attached to an accepted request.

## Coordinated activation

Review and deploy `submitAccessRequest` and `getAccessRequestStatus`, their shared
modules and the updated Firestore rules only to your own Firebase project.
Existing profile-update, approval and withdrawal handlers keep their entry points
and remain compatible with the shared reservation's UID format. No Storage-rule
change or additional composite index is required.

When enabling email uniqueness, deploy the shared-module update in
`submitAccessRequest`, `updateOwnProfile`, `reviewAccessRequest`, and `removeNeighbor`
together. No additional rules change or APK change is needed for email validation
once the callable-based request flow above is installed. Do not deploy only the
submission handler while leaving profile corrections on the old implementation.

Use the updated Android application with these changes. Once the new Firestore
rules are active, older APKs that write access requests directly cannot submit
new requests. Do not activate the rules without coordinating the updated APK.
An APK built from this source cannot use the new submission flow against a backend
that has not deployed `submitAccessRequest` yet.

## Local verification

```powershell
node --test functions/test/access_request_submission.test.cjs
flutter analyze
flutter test
```

`functions/test/access_request_submission.emulator.test.cjs` additionally uses the
official local Firestore and Authentication emulators with the fixed project
`demo-micomunidad-access-requests`. Set `FIRESTORE_EMULATOR_HOST` and
`FIREBASE_AUTH_EMULATOR_HOST` to their respective `127.0.0.1:PORT` addresses first.
It refuses other hosts and skips when the emulators are not configured. Storage
metadata and email delivery are simulated; no live community data is used.
