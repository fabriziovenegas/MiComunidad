// Public hint only: never return an address usable for sending email.
function maskPublicEmail(value) {
  const email = typeof value === "string" ? value.trim() : "";
  if (/^[^@\s*]{0,2}\*{4}@\*{3}\.[a-z]{2,24}$/i.test(email)) return email;
  if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,24}$/i.test(email)) return "";
  const [local, domain] = email.split("@");
  const prefix = local.slice(0, Math.min(2, local.length - 1));
  const suffix = domain.slice(domain.lastIndexOf(".") + 1).toLowerCase();
  return `${prefix}****@***.${suffix}`;
}

module.exports = {maskPublicEmail};
