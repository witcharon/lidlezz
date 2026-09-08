# lidlezz.app

Static site (Cloudflare Pages, root = this folder) plus a Worker that turns Stripe payments into license keys.

1. `cd worker && node keygen.mjs` → public key into `Sources/LidlezzCore/License.swift`, private key kept secret.
2. `wrangler secret put STRIPE_SECRET_KEY`, `LICENSE_PRIVATE_KEY`, `RESEND_API_KEY`; `wrangler deploy`.
3. Stripe › Payment Links: create one for the product, set the success URL to
   `https://lidlezz.app/thanks.html?session_id={CHECKOUT_SESSION_ID}`, paste the link into `index.html` (STRIPE_PAYMENT_LINK).
4. Put the Worker URL into `thanks.html` (WORKER).
5. `scripts/release.sh` writes `dist/latest.json`; copy it here so the Download button and the in-app update check follow releases.
