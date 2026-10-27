// Explicit maintenance operation, never an automatic deployed endpoint.
// Dry-run is the default. It revokes bearer URLs without deleting any file.
async function revokeLegacyDownloadTokens({bucket, apply = false}) {
  let candidates = 0;
  let revocationRequests = 0;
  for (const prefix of ["projects/", "reports/", "events/", "access_requests/"]) {
    const [files] = await bucket.getFiles({prefix});
    for (const file of files) {
      const parts = file.name.split("/");
      const allowed = parts.length === 4 && (
        (["projects", "reports"].includes(parts[0]) && parts[2] === "photos") ||
        (parts[0] === "events" && ["photos", "minutes"].includes(parts[2])) ||
        (parts[0] === "access_requests" && parts[2] === "identity"));
      if (!allowed || parts.some((part) => !part || [".", ".."].includes(part))) continue;
      const [metadata] = await file.getMetadata();
      if (!metadata.metadata?.firebaseStorageDownloadTokens) continue;
      candidates++;
      if (apply) {
        await file.setMetadata({metadata: {...metadata.metadata, firebaseStorageDownloadTokens: null}},
            {ifMetagenerationMatch: metadata.metageneration});
        revocationRequests++;
      }
    }
  }
  return {candidates, revocationRequests, dryRun: !apply};
}

module.exports = {revokeLegacyDownloadTokens};
