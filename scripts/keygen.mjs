// Makes the Ed25519 pair that signs licenses. Run once: node keygen.mjs
// Public key goes into Sources/LidlezzCore/License.swift, private key into `wrangler secret put LICENSE_PRIVATE_KEY`.
import { generateKeyPairSync } from "node:crypto";
const { publicKey, privateKey } = generateKeyPairSync("ed25519");
const pub = publicKey.export({ type: "spki", format: "der" }).subarray(-32).toString("base64");
const priv = privateKey.export({ type: "pkcs8", format: "der" }).toString("base64");
console.log("PUBLIC (License.swift):", pub);
console.log("PRIVATE (wrangler secret):", priv);
