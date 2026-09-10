// Local check of the license format: node sign.mjs <private key base64> <email> [id secret]
import { createHmac, createPrivateKey, sign } from "node:crypto";
const [priv, email, idSecret = "test"] = process.argv.slice(2);
const id = createHmac("sha256", idSecret).update(email.trim().toLowerCase()).digest("hex").slice(0, 16);
const key = createPrivateKey({ key: Buffer.from(priv, "base64"), format: "der", type: "pkcs8" });
const payload = Buffer.from(
  JSON.stringify({ e: email, t: Math.floor(Date.now() / 1000), i: id }),
);
const b64u = (b) => b.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
console.log(`LZ-${b64u(payload)}.${b64u(sign(null, payload, key))}`);
