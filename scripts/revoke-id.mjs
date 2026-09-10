// Prints the license id for a buyer's email, so you can revoke every key ever issued to them.
// The id is a keyed hash: same email always gives the same id, and the published list stays opaque.
//   node scripts/revoke-id.mjs someone@example.com
// Add the printed id to lidlezz-web/public/revoked.json and redeploy.
import { createHmac } from "node:crypto";
import { execFileSync } from "node:child_process";

const email = process.argv[2];
if (!email) {
  console.error("usage: node scripts/revoke-id.mjs <email>");
  process.exit(1);
}
const secret = execFileSync("security", ["find-generic-password", "-a", "lidlezz-id", "-w"]).toString().trim();
console.log(licenseID(email, secret));

export function licenseID(email, secret) {
  return createHmac("sha256", secret).update(email.trim().toLowerCase()).digest("hex").slice(0, 16);
}
