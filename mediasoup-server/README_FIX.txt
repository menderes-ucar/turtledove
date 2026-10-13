BESTIE mediasoup server auth-env fix

The error "SUPABASE_URL/SUPABASE_ANON_KEY required when auth is enabled" was caused by the start script not loading .env.

IMPORTANT:
- Keep your existing .env file in this same folder.
- Do NOT paste or commit the real anon key/access tokens into source files.
- REQUIRE_SUPABASE_AUTH should remain true.

Expected .env entries (values already known to your existing setup):
PORT=4000
MEDIASOUP_ANNOUNCED_IP=192.168.1.9
MEDIASOUP_MIN_PORT=20000
MEDIASOUP_MAX_PORT=20100
REQUIRE_SUPABASE_AUTH=true
SUPABASE_URL=...
SUPABASE_ANON_KEY=...

Start from this folder:
  npm install
  npm start

Or directly:
  node --env-file=.env server.js

Safe env check (does not print secrets):
  node --env-file=.env -e "console.log({url:!!process.env.SUPABASE_URL, anon:!!process.env.SUPABASE_ANON_KEY, auth:process.env.REQUIRE_SUPABASE_AUTH})"

Expected:
  { url: true, anon: true, auth: 'true' }
