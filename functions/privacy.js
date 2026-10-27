// Public hint only. Keep short local parts mostly or completely hidden.
function maskPublicEmail(value) {
  const email = typeof value === "string" ? value.trim() : "";
  // Older backends hid the domain as well; never expand an existing mask.
  if (/^[^@\s*]{0,2}\*{4}@\*{3}\.[a-z]{2,24}$/i.test(email)) return email;
  if (email.length > 320 || !/^[^@\s]+@[^@\s]+\.[a-z]{2,63}$/i.test(email)) return "";
  const [local, domain] = email.split("@");
  if (domain.includes("*")) return "";
  const normalizedDomain = domain.toLowerCase();
  // Defensive idempotency for a response already masked by this backend.
  if (local.includes("*")) {
    return /^[^@\s*]{0,2}\*{3,}[^@\s*]?$/u.test(local) ?
      `${local}@${normalizedDomain}` : `****@${normalizedDomain}`;
  }
  const characters = Array.from(local);
  if (characters.length <= 3) return `****@${normalizedDomain}`;
  if (characters.length <= 5) {
    return `${characters[0]}${"*".repeat(characters.length - 1)}@${normalizedDomain}`;
  }
  return `${characters.slice(0, 2).join("")}${"*".repeat(characters.length - 3)}${characters.at(-1)}@${normalizedDomain}`;
}

module.exports = {maskPublicEmail};
