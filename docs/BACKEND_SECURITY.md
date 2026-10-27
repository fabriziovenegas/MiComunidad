# Backend access and private attachments

This describes the locally prepared security update. It does not confirm that a
Firebase deployment or historical download-link cleanup has been performed.

## Access

| Account | Allowed backend access |
| --- | --- |
| No session | Public community counts and the existing DNI status lookup. Password recovery continues through Firebase Authentication. |
| Automatic anonymous session | Upload its own identity document and submit an access request. This does not grant membership. |
| Signed in, not approved | No resident or administrator content. |
| Approved resident | The existing resident features, with author ownership, parent visibility, content states and field validation enforced by Firebase. |
| Approved administrator | Administrative features. Report content remains author-only, including the existing exception allowing an administrator to edit their own resolved report. |

Firestore and Storage check the current membership document. A withdrawn member or
demoted administrator cannot retain permissions merely by keeping an older token.
Direct profile updates are disabled; the existing `updateOwnProfile` function keeps
Authentication, profiles, requests and identity indexes synchronized.

New records have explicit allowed fields, types, lengths, states and server dates.
Unchanged legacy project/activity fields are preserved when archiving or making an
unrelated edit. Comment authors come from the authenticated member's current profile.

## Attachments

`registerContentAttachment` checks current membership, the parent record, uploader,
upload ID, object path, real Storage metadata, size, MIME and a matching format header.
It generates the stored reference itself. A caller cannot publish an arbitrary URL,
bucket, owner or unrelated object. Header identification is not a full image decoder
or malware scanner.

The client uploads bytes with stable IDs as before, then calls this registration
function. Retries and offline queues keep those IDs. Direct attachment-record creation
is denied. Member deletion uses `deleteContentAttachment`, which derives its target
from the stored record and checks parent ownership; client-supplied deletion paths
and URLs are rejected. Administrative archive cleanup remains available.

New references use `gs://` without a download token. Photos use authenticated Storage
downloads. Documents are downloaded with the same authorization and opened on Android
through a non-exported FileProvider and a temporary read-only URI. External URLs and
other buckets are refused. Public welcome assets and map-service attribution links
are unaffected.

## Activation must be coordinated

- Update only `submitAccessRequest`, `reviewAccessRequest`, `removeNeighbor`,
  `setUserRole`, `updateOwnProfile`, `registerContentAttachment` and
  `deleteContentAttachment` as applicable to this update.
- Update Firestore and Storage rules and use the matching new Android build.
- Coordinate this rollout: older builds write attachment metadata directly and
  cannot display the new `gs://` references. Do not activate stricter rules while
  expecting those older builds to continue uploading normally.
- Review historical bearer links separately. `download_token_cleanup.js` is an
  explicit maintenance helper with a dry-run default, not a callable or scheduled
  function. Applying it changes only download-token metadata and preserves files.
  Historical token removal requires separate approval and verification.
- Confirm the Functions service account can read/update/delete the relevant Storage
  objects. No IAM changes are included in this local update.
- The unused password-code functions are locally disabled. The app uses Firebase's
  password-reset email; do not deploy those legacy exports as part of this update.

## Verification and limits

Local tests use fixed `demo-` project IDs, fictitious records and loopback emulators.
They include direct Firestore, Storage and callable HTTP requests without Flutter.

The official Storage emulator keeps download tokens separately and does not reproduce
GCS custom-metadata key deletion with `null`. The HTTP token-revocation assertion is
explicitly skipped, rather than reported as passing. The metadata-update contract is
unit-tested. Actual invalidation of an old URL must be checked with a disposable
Firebase object after separate authorization, before applying historical cleanup.

These controls do not require App Check. They do not set request-rate or account-wide
storage quotas, verify civil identity, or prevent an authorized recipient from copying
content already downloaded. Those concerns require separate decisions.

References: [Firestore field validation](https://firebase.google.com/docs/firestore/security/rules-fields),
[Storage rule access-call limits](https://firebase.google.com/docs/rules/rules-behavior),
[GCS metadata editing and key removal](https://docs.cloud.google.com/storage/docs/viewing-editing-metadata).
