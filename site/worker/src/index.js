// Cloudflare Worker: turns a paid Stripe Checkout session into a signed Lidlezz license.
//   GET  /license?session_id=cs_…   → { license, email }   (called by thanks.html right after checkout)
//   POST /license/recover {email}   → emails the license again through Resend
// Secrets: STRIPE_SECRET_KEY, LICENSE_PRIVATE_KEY (pkcs8 base64 from keygen.mjs), RESEND_API_KEY. Var: FROM_EMAIL.

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "access-control-allow-origin": "*" } });

const b64u = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function mint(env, email) {
  const der = Uint8Array.from(atob(env.LICENSE_PRIVATE_KEY), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "Ed25519" }, false, ["sign"]);
  const payload = new TextEncoder().encode(JSON.stringify({ e: email, t: Math.floor(Date.now() / 1000) }));
  const sig = await crypto.subtle.sign({ name: "Ed25519" }, key, payload);
  return `LZ-${b64u(payload)}.${b64u(sig)}`;
}

async function stripe(env, path) {
  const r = await fetch(`https://api.stripe.com/v1/${path}`, { headers: { authorization: `Bearer ${env.STRIPE_SECRET_KEY}` } });
  return r.json();
}

async function paidEmailForSession(env, id) {
  const s = await stripe(env, `checkout/sessions/${id}`);
  return s.payment_status === "paid" ? s.customer_details?.email : null;
}

async function hasPaid(env, email) {
  const q = encodeURIComponent(`status:'complete'`);
  const list = await stripe(env, `checkout/sessions?limit=100&customer_details[email]=${encodeURIComponent(email)}`);
  return (list.data ?? []).some((s) => s.payment_status === "paid");
}

async function email(env, to, license) {
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      from: env.FROM_EMAIL, to, subject: "Your Lidlezz license",
      text: `Here is your Lidlezz license key:\n\n${license}\n\nOpen Lidlezz › Enter license and paste it.`,
    }),
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return json({});

    if (request.method === "GET" && url.pathname === "/license") {
      const id = url.searchParams.get("session_id");
      const buyer = id && (await paidEmailForSession(env, id));
      if (!buyer) return json({ error: "no paid session" }, 402);
      return json({ email: buyer, license: await mint(env, buyer) });
    }

    if (request.method === "POST" && url.pathname === "/license/recover") {
      const { email: addr } = await request.json().catch(() => ({}));
      if (!addr) return json({ error: "email required" }, 400);
      if (await hasPaid(env, addr)) await email(env, addr, await mint(env, addr));
      return json({ ok: true }); // same answer either way, so the endpoint cannot be used to probe buyers
    }

    return json({ error: "not found" }, 404);
  },
};
