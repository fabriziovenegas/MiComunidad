# Current report author names

Report ownership remains `createdBy`, an account UID. `createdByName` stays as the original display-name snapshot and fallback; changing a profile does not rewrite reports.

`getReportAuthorName` is a read-only callable. It takes a report ID (not a user ID), checks the caller's approved profile, and verifies report visibility before returning only `{name}`. Approved administrators can read existing reports; approved residents can read their own reports or approved reports in the visible operational states. A missing/inaccessible report produces the same permission error. An absent author account/name returns null.

The app uses the existing signed-in profile for one's own reports, so a profile-name change is reflected without a second lookup. For other authors it retrieves the name when the label is opened/mounted and when the app resumes. It does not continuously monitor all profiles. Offline, unavailable or removed-account cases retain the saved name, or `Vecino` if none was stored.

No new profile read permissions, collections, migrations or report writes are required. Personal identifiers, contact details, role and address are not returned. Comment-author labels are outside this change.

Deploy only `functions:getReportAuthorName`, using the intended Firebase project, and rebuild/restart the client to include the label change. Existing Functions and Firestore/Storage rules do not need deployment.
