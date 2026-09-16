# BlinkCast backend

This is the Cloudflare Worker backend for BlinkCast. It provides:

- Five-digit join-code registration and lookup
- Password-protected room lookup
- A WebSocket signaling endpoint
- One Durable Object room per BlinkCast room
- Host/viewer presence notifications
- Offer, answer, and ICE candidate routing

The backend does not carry video. WebRTC sends video directly between devices, using TURN only when a direct connection is not possible.

## 1. Install Node.js

Install the current LTS version from https://nodejs.org/.

Close and reopen your terminal after installing it. Verify:

```sh
node --version
npm --version
```

## 2. Install dependencies

From this `backend` directory:

```sh
npm install
```

## 3. Log in to Cloudflare

Create or log in to a Cloudflare account at https://dash.cloudflare.com/.

Then run:

```sh
npx wrangler login
```

A browser window will open. Approve the login.

## 4. Test locally

```sh
npm run dev
```

Wrangler prints a local URL, normally:

```text
http://localhost:8787
```

The local WebSocket endpoint is:

```text
ws://localhost:8787/signal?roomId=test-room
```

## 5. Deploy

```sh
npm run deploy
```

Wrangler prints a URL like:

```text
https://blinkcast-signaling.<your-subdomain>.workers.dev
```

The signaling URL for the Apple app is:

```text
wss://blinkcast-signaling.<your-subdomain>.workers.dev/signal
```

The registration endpoints are on the same hostname:

```text
https://blinkcast-signaling.<your-subdomain>.workers.dev/register
https://blinkcast-signaling.<your-subdomain>.workers.dev/resolve
```

## 6. Configure BlinkCast

Open the Host screen and enter the deployed WebSocket URL in the signaling URL field:

```text
wss://blinkcast-signaling.<your-subdomain>.workers.dev/signal
```

The Worker adds the room ID to the returned `wsUrl`, so the existing Apple signaling client can connect to the correct Durable Object.

## 7. Configure production TURN

The Worker intentionally has no fake TURN values. Add real relay credentials
before deploying:

Create a TURN key in Cloudflare Realtime, then store the key ID and the API
token used to generate short-lived credentials:

```sh
npx wrangler secret put TURN_KEY_ID
npx wrangler secret put TURN_API_TOKEN
```

BlinkCast generates one-hour credentials from Cloudflare for each configuration
request. Cloudflare's TURN endpoints are `turn.cloudflare.com` on UDP 3478 and
TLS 5349/443; the Worker receives the complete server list from Cloudflare.

Verify the configuration with:

```sh
curl https://blinkcast-signaling.<your-subdomain>.workers.dev/turn-config
```

Do not commit TURN credentials or placeholder values to `wrangler.toml`.

## 8. What a successful session does

1. Host calls `/register`.
2. Worker creates a five-digit code.
3. Host opens `/signal?roomId=...`.
4. Viewer calls `/resolve` with the code.
5. Viewer opens the returned WebSocket URL.
6. The Worker sends `host-available`.
7. Viewer sends a WebRTC offer.
8. Worker forwards the offer to the host.
9. Host sends an answer.
10. Worker forwards the answer to the viewer.
11. Both peers exchange ICE candidates.
12. WebRTC carries the video.

## Important production work

Before public release:

- Add authentication tokens to WebSocket joins.
- Rate-limit code resolution.
- Add a real TURN service such as coturn, Cloudflare Realtime TURN, Metered, or Twilio.
- Add viewer approval messages.
- Add per-viewer peer connections for multiple viewers.
- Use a custom domain and `wss://` in production.
