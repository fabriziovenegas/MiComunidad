# Protecting the last administrator

`setUserRole` checks the caller's current approved administrator profile, the
target's current profile, and the remaining approved administrators inside one
Firestore transaction. Retries recheck all these conditions before committing.
Self-role changes remain prohibited. A profile being withdrawn cannot be promoted.

If two administrators try to demote each other simultaneously, one change can
commit and the other fails after rechecking its caller's role. This does not
promise ordering by the time a user taps a button on a device. No queue, counter,
new collection or manual migration is used. Existing user records are preserved
except for the target's role and update timestamp.

Authentication custom claims are updated only after a successful Firestore commit.
Other custom claims are preserved. If another role change supersedes the first,
the handler rechecks the current role and reconciles claims with bounded retries.
An Authentication failure never rolls a committed role back; the caller receives
an explicit synchronization error and may retry the role update. Firestore and
Authentication cannot commit atomically together, so temporary synchronization
failures remain possible. Existing ID tokens refresh under the normal Firebase
Authentication lifecycle; this change does not promise immediate token revocation.

## Verification and activation

Unit tests in `functions/test/role_management.test.cjs` cover authorization,
concurrent demotions, unchanged fields, claims preservation, failures and retries.
`functions/test/role_management.emulator.test.cjs` runs against loopback-only
Firestore and Authentication emulators under `demo-micomunidad-role-management`.
It creates only fictional local users. It skips without emulator hosts and refuses
non-loopback hosts. Never point these tests at production credentials.

Deploy only the updated `setUserRole` function to activate this correction. No
Firestore/Storage rule change, new APK, real-account test or data migration is
required. Deployment must be authorized separately from local implementation.
