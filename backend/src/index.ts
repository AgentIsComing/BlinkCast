export interface Env {
  ROOMS: DurableObjectNamespace;
  CODES: DurableObjectNamespace;
  ROOM_TTL_SECONDS: string;
  MAX_VIEWERS_PER_ROOM?: string;
  SESSION_SECRET?: string;
  PASSWORD_SALT?: string;
  ALLOWED_SIGNAL_HOSTS?: string;
  TURN_SERVERS?: string;
  TURN_USERNAME?: string;
  TURN_CREDENTIAL?: string;
  TURN_KEY_ID?: string;
  TURN_API_TOKEN?: string;
}

type Role = "host" | "viewer";

type CodeRecord = {
  roomId: string;
  wsUrl: string;
  passwordHash?: string;
  expiresAt: number;
};

type ClientInfo = {
  role: Role;
  roomId: string;
  clientId: string;
};

type ViewerInfo = ClientInfo & {
  status: "pending" | "approved" | "denied";
  joinedAt: number;
};

type ViewerMetrics = ViewerInfo & {
  bitrate: number;
  packetLoss: number;
  rtt: number;
  networkQuality: string;
  lastUpdate: number;
};

type RoomAnalytics = {
  roomId: string;
  totalViewers: number;
  approvedViewers: number;
  pendingViewers: number;
  deniedViewers: number;
  totalBitrate: number;
  averageLatency: number;
  averagePacketLoss: number;
  isHostActive: boolean;
  sessionDuration: number;
  peakViewerCount: number;
};

type DiagnosticsReport = {
  roomId: string;
  clientId: string;
  role: Role;
  timestamp: number;
  networkQuality: string;
  iceState: string;
  bitrate: number;
  packetLoss: number;
  rtt: number;
};

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": "content-type"
};

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: jsonHeaders
  });
}

function ttl(env: Env): number {
  const value = Number.parseInt(env.ROOM_TTL_SECONDS || "900", 10);
  return Number.isFinite(value) && value > 0 ? value : 900;
}

function maxViewers(env: Env): number {
  const value = Number.parseInt(env.MAX_VIEWERS_PER_ROOM || "8", 10);
  return Number.isFinite(value) && value > 0 ? value : 8;
}

export function normalizePushRegistration(input: Record<string, unknown>): {
  deviceToken: string;
  platform: "ios" | "android";
  roomId?: string;
} | null {
  if (typeof input.deviceToken !== "string") return null;
  const deviceToken = input.deviceToken.trim();
  if (!deviceToken || deviceToken.length < 12 || deviceToken.length > 256) return null;

  const platformValue = typeof input.platform === "string" ? input.platform.toLowerCase() : "ios";
  if (platformValue !== "ios" && platformValue !== "android") return null;

  const roomId = typeof input.roomId === "string" ? input.roomId.trim() : undefined;

  return {
    deviceToken,
    platform: platformValue,
    ...(roomId && roomId.length > 0 ? { roomId } : {})
  };
}

export function normalizePushNotification(input: Record<string, unknown>): {
  deviceToken: string;
  title: string;
  body: string;
  type: "approval" | "room-start";
  aps: { alert: { title: string; body: string } };
} | null {
  const registration = normalizePushRegistration({
    deviceToken: input.deviceToken,
    platform: input.platform ?? "ios"
  });
  if (!registration) return null;

  const title = typeof input.title === "string" ? input.title.trim() : "";
  const body = typeof input.body === "string" ? input.body.trim() : "";
  const typeValue = typeof input.type === "string" ? input.type.toLowerCase() : "";

  if (!title || !body || (typeValue !== "approval" && typeValue !== "room-start")) return null;

  return {
    deviceToken: registration.deviceToken,
    title,
    body,
    type: typeValue,
    aps: {
      alert: {
        title,
        body
      }
    }
  };
}

export function getSecretValue(
  env: Partial<Record<string, string | undefined>>,
  key: string,
  fallback = "blinkcast-default-secret"
): string {
  const value = typeof env[key] === "string" ? env[key]!.trim() : "";
  if (!value) return fallback;

  const forbidden = new Set([
    "change-me",
    "replace-me",
    "blinkcast-default-secret",
    "blinkcast-dev-salt-change-me",
    "dev-secret",
    "default-secret"
  ]);

  if (forbidden.has(value.toLowerCase())) {
    return fallback;
  }

  return value;
}

export function buildRateLimitKey(input: {
  action: string;
  clientIP?: string;
  roomId?: string;
  code?: string;
}): string {
  const action = input.action || "unknown";
  const clientIP = (input.clientIP || "unknown").trim() || "unknown";
  const roomId = (input.roomId || input.code || "global").trim() || "global";
  return `${action}:${clientIP}:${roomId}`;
}

function sessionSecret(env: Env): string {
  const primary = getSecretValue(env as Partial<Record<string, string | undefined>>, "SESSION_SECRET", "blinkcast-default-secret");
  const fallback = getSecretValue(env as Partial<Record<string, string | undefined>>, "PASSWORD_SALT", primary);
  return primary === "blinkcast-default-secret" ? fallback : primary;
}

function normalizeRoomId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const roomId = value.trim().toLowerCase();
  if (!roomId || roomId.length > 128) return null;
  return roomId;
}

function randomCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(10000 + (bytes[0] % 90000));
}

function clientAddress(request: Request): string {
  return request.headers.get("CF-Connecting-IP")
    || request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim()
    || "unknown";
}

function allowedSignalHosts(env: Env, request: Request): Set<string> {
  const hosts = new Set<string>();
  const requestHost = new URL(request.url).hostname.toLowerCase();
  if (requestHost) hosts.add(requestHost);

  const configured = (env.ALLOWED_SIGNAL_HOSTS ?? "")
    .split(",")
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean);

  for (const host of configured) {
    hosts.add(host);
  }

  return hosts;
}

export function normalizeSignalURL(value: string): URL | null {
  const trimmed = value.trim();
  if (!trimmed) return null;

  let normalizedValue = trimmed;
  if (normalizedValue.startsWith("https://")) {
    normalizedValue = "wss://" + normalizedValue.slice("https://".length);
  }
  if (normalizedValue.startsWith("http://")) {
    normalizedValue = "ws://" + normalizedValue.slice("http://".length);
  }

  if (!normalizedValue.startsWith("ws://") && !normalizedValue.startsWith("wss://")) {
    return null;
  }

  const parsed = new URL(normalizedValue);
  const host = parsed.hostname.toLowerCase();
  if (!parsed.hostname || host === "localhost" || host === "127.0.0.1" || host === "::1") {
    return null;
  }

  const path = parsed.pathname.replace(/\/+$/, "");
  if (!path || path === "/") {
    parsed.pathname = "/signal";
  } else if (!path.endsWith("/signal") && !path.endsWith("signal")) {
    parsed.pathname = `${path.replace(/\/+$/, "")}/signal`;
  }

  if (!parsed.protocol || (parsed.protocol !== "ws:" && parsed.protocol !== "wss:")) {
    return null;
  }

  return parsed;
}

export function isAllowedSignalURL(value: string, requestURL: string, hosts?: Iterable<string>): boolean {
  const parsed = normalizeSignalURL(value);
  if (!parsed) return false;

  const allowList = hosts ? [...hosts].map((host) => host.toLowerCase().trim()) : [];
  const requestHost = new URL(requestURL).hostname.toLowerCase();
  const targetHost = parsed.hostname.toLowerCase();
  const isAllowedHost = allowList.some((allowedHost) => {
    if (allowedHost.startsWith("*.")) {
      const suffix = allowedHost.slice(1);
      return targetHost.endsWith(suffix) && targetHost.length > suffix.length;
    }
    return targetHost === allowedHost;
  });

  if (allowList.length > 0 && !isAllowedHost && targetHost !== requestHost) {
    return false;
  }

  if (targetHost === requestHost) {
    return true;
  }

  return isAllowedHost;
}

export async function hashPassword(password: string, salt: string): Promise<string> {
  const input = `${salt}:${password}`;
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function verifyPassword(password: string, expectedHash: string, salt = "blinkcast-default-salt"): Promise<boolean> {
  return (await hashPassword(password, salt)) === expectedHash;
}

export type SessionTokenClaims = {
  roomId: string;
  code: string;
  purpose: "resolve" | "register";
  exp: number;
};

function encodeBase64Url(value: ArrayBuffer): string {
  const bytes = new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function decodeBase64Url(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let idx = 0; idx < binary.length; idx += 1) {
    bytes[idx] = binary.charCodeAt(idx);
  }
  return bytes;
}

async function hmacSha256(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return encodeBase64Url(signature);
}

export async function createSessionToken(claims: SessionTokenClaims, secret: string): Promise<string> {
  const header = encodeBase64Url(new TextEncoder().encode(JSON.stringify({ alg: "HS256", typ: "session" })));
  const payload = encodeBase64Url(new TextEncoder().encode(JSON.stringify(claims)));
  const signingInput = `${header}.${payload}`;
  const signature = await hmacSha256(secret, signingInput);
  return `${signingInput}.${signature}`;
}

export async function verifySessionToken(token: string, secret: string, expected: SessionTokenClaims): Promise<boolean> {
  if (!token || token.split(".").length !== 3) return false;

  const [header, payload, signature] = token.split(".");
  if (!header || !payload || !signature) return false;

  const signingInput = `${header}.${payload}`;
  const expectedSignature = await hmacSha256(secret, signingInput);
  if (signature !== expectedSignature) return false;

  try {
    const decoded = JSON.parse(new TextDecoder().decode(decodeBase64Url(payload))) as Partial<SessionTokenClaims>;
    const now = Math.floor(Date.now() / 1000);
    const hasRoom = decoded.roomId === expected.roomId;
    const hasCode = decoded.code === expected.code;
    const hasPurpose = decoded.purpose === expected.purpose;
    const hasExpiry = typeof decoded.exp === "number" && decoded.exp > now;
    return hasRoom && hasCode && hasPurpose && hasExpiry;
  } catch {
    return false;
  }
}

export async function validateJoinAuthorization(
  input: { roomId: string; code?: string; token: string; role: Role },
  secret: string
): Promise<boolean> {
  if (!input.roomId || !input.token) return false;
  if (input.role !== "viewer" && input.role !== "host") return false;

  const normalizedCode = input.code ?? "";
  const tokenClaims: SessionTokenClaims = {
    roomId: input.roomId,
    code: normalizedCode,
    purpose: "resolve",
    exp: Math.floor(Date.now() / 1000) + 300
  };

  const isValid = await verifySessionToken(input.token, secret, tokenClaims);
  return isValid;
}

async function readJSON(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    return typeof value === "object" && value !== null
      ? value as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function signalURL(request: Request): string {
  const url = new URL(request.url);
  return `${url.origin}/signal`;
}

function roomSignalURL(value: string, roomId: string): string {
  const url = new URL(value);
  url.searchParams.set("roomId", roomId);
  return url.toString();
}

function roomPasswordSalt(env: Env, roomId: string): string {
  const configured = (env.PASSWORD_SALT ?? "").trim();
  return configured ? `${configured}:${roomId}` : `blinkcast-room:${roomId}`;
}

async function authorizeRoomRequest(
  request: Request,
  env: Env,
  roomId: string,
  code: string
): Promise<boolean> {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  return Boolean(token && roomId && await verifySessionToken(token, sessionSecret(env), {
    roomId,
    code,
    purpose: "resolve",
    exp: Math.floor(Date.now() / 1000) + 1
  }));
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { headers: jsonHeaders });

    const url = new URL(request.url);

    if (url.pathname === "/diagnostics") {
      if (request.method !== "POST") {
        return json({ error: "POST required." }, 400);
      }

      const body = await readJSON(request);
      const report: DiagnosticsReport = {
        roomId: typeof body.roomId === "string" ? body.roomId : "",
        clientId: typeof body.clientId === "string" ? body.clientId : "",
        role: body.role === "host" || body.role === "viewer" ? body.role : "viewer",
        timestamp: Math.floor(Date.now() / 1000),
        networkQuality: typeof body.networkQuality === "string" ? body.networkQuality : "unknown",
        iceState: typeof body.iceState === "string" ? body.iceState : "unknown",
        bitrate: typeof body.bitrate === "number" ? body.bitrate : 0,
        packetLoss: typeof body.packetLoss === "number" ? body.packetLoss : 0,
        rtt: typeof body.rtt === "number" ? body.rtt : 0
      };
      if (!await authorizeRoomRequest(request, env, report.roomId, typeof body.code === "string" ? body.code : "")) {
        return json({ error: "Diagnostics authorization required." }, 401);
      }

      const diagnosticsId = env.CODES.idFromName(`diagnostics:${report.roomId}`);
      await env.CODES.get(diagnosticsId).fetch(
        new Request("https://diagnostics/record", {
          method: "POST",
          body: JSON.stringify(report)
        })
      );

      return json({ success: true, timestamp: report.timestamp });
    }

    if (url.pathname === "/diagnostics/room") {
      const roomId = url.searchParams.get("roomId");
      if (!roomId) return json({ error: "roomId is required." }, 400);
      if (!await authorizeRoomRequest(request, env, roomId, url.searchParams.get("code") ?? "")) {
        return json({ error: "Diagnostics authorization required." }, 401);
      }

      const diagnosticsId = env.CODES.idFromName(`diagnostics:${roomId}`);
      const response = await env.CODES.get(diagnosticsId).fetch(
        new Request("https://diagnostics/list")
      );
      if (!response.ok) return json({ error: "Could not retrieve diagnostics." }, 503);
      const reports = await response.json() as DiagnosticsReport[];
      return json({ roomId, reports });
    }

    if (url.pathname === "/turn-config") {
      const authorization = request.headers.get("authorization") ?? "";
      const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
      const roomId = normalizeRoomId(url.searchParams.get("roomId"));
      const code = url.searchParams.get("code") ?? "";
      const authorized = roomId && token
        ? await verifySessionToken(token, sessionSecret(env), {
            roomId,
            code,
            purpose: "resolve",
            exp: Math.floor(Date.now() / 1000) + 1
          })
        : false;
      if (!authorized) return json({ error: "TURN configuration authorization required." }, 401);

      if (env.TURN_KEY_ID && env.TURN_API_TOKEN) {
        const turnResponse = await fetch(
          `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(env.TURN_KEY_ID)}/credentials/generate-ice-servers`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${env.TURN_API_TOKEN}`,
              "content-type": "application/json"
            },
            body: JSON.stringify({ ttl: 86400 })
          }
        );

        if (!turnResponse.ok) {
          return json({ error: "Could not generate TURN credentials." }, 503);
        }

        const turnConfig = await turnResponse.json() as {
          iceServers?: Array<{ urls?: string[]; username?: string; credential?: string }>;
        };
        const relay = turnConfig.iceServers?.find((server) => server.username && server.credential);
        if (!relay?.urls?.length || !relay.username || !relay.credential) {
          return json({ error: "TURN provider returned an incomplete configuration." }, 503);
        }

        return json({
          servers: relay.urls.filter((server) => !server.includes(":53")),
          username: relay.username,
          credential: relay.credential,
          ttl: 86400
        });
      }

      const turnServers = (env.TURN_SERVERS ?? "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      const username = env.TURN_USERNAME ?? "";
      const credential = env.TURN_CREDENTIAL ?? "";

      if (turnServers.length === 0 || !username || !credential) {
        return json({ error: "TURN server configuration is incomplete." }, 503);
      }

      return json({
        servers: turnServers,
        username,
        credential,
        ttl: 3600
      });
    }

    if (url.pathname === "/signal") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return json({ error: "WebSocket upgrade required." }, 426);
      }

      const roomId = normalizeRoomId(url.searchParams.get("roomId"));
      if (!roomId) return json({ error: "roomId is required." }, 400);
      const id = env.ROOMS.idFromName(roomId);
      const roomHeaders = new Headers(request.headers);
      roomHeaders.set("x-blinkcast-session-secret", sessionSecret(env));
      roomHeaders.set("x-blinkcast-max-viewers", String(maxViewers(env)));
      return env.ROOMS.get(id).fetch(new Request(request, { headers: roomHeaders }));
    }

    if (request.method !== "POST") {
      return json({
        service: "BlinkCast signaling and join-code service",
        endpoints: ["/register", "/register-room", "/resolve", "/resolve-room", "/signal"]
      });
    }

    const body = await readJSON(request);
    if (Number(request.headers.get("content-length") || "0") > 32_768) {
      return json({ error: "Request is too large." }, 413);
    }

    const roomId = normalizeRoomId(body.roomId);
    const requestedWsUrl = typeof body.wsUrl === "string" && body.wsUrl.length > 0
      ? body.wsUrl
      : signalURL(request);
    const allowedHosts = allowedSignalHosts(env, request);
    if (!isAllowedSignalURL(requestedWsUrl, request.url, allowedHosts)) {
      return json({ error: "Signal URL is not trusted for this deployment." }, 400);
    }
    const normalizedWsUrl = normalizeSignalURL(requestedWsUrl)?.toString() ?? requestedWsUrl;
    const wsUrl = roomId ? roomSignalURL(normalizedWsUrl, roomId) : normalizedWsUrl;
    const expiresIn = ttl(env);

    if (url.pathname === "/register") {
      if (!roomId) return json({ error: "roomId is required." }, 400);
      const clientIp = clientAddress(request);
      const rateKey = buildRateLimitKey({ action: "register", clientIP: clientIp, roomId });
      const allowed = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request("https://codes/rate-limit", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ key: rateKey })
        })
      );
      if (!allowed.ok) return json({ error: "Too many registration attempts. Try again later." }, 429);
      let code = randomCode();
      for (let attempt = 0; attempt < 10; attempt += 1) {
        const existing = await env.CODES.get(
          env.CODES.idFromName("registry")
        ).fetch(new Request("https://codes/claim", {
          method: "POST",
          body: JSON.stringify({
            code,
            record: { roomId, wsUrl, expiresAt: Date.now() + expiresIn * 1000 }
          })
        }));
        if (existing.ok) break;
        code = randomCode();
      }
      const token = await createSessionToken(
        { roomId, code, purpose: "resolve", exp: Math.floor(Date.now() / 1000) + 86400 },
        sessionSecret(env)
      );
      return json({ code, roomId, wsUrl, sessionToken: token });
    }

    if (url.pathname === "/register-room") {
      if (!roomId) return json({ error: "roomId is required." }, 400);
      const clientIp = clientAddress(request);
      const rateKey = buildRateLimitKey({ action: "register", clientIP: clientIp, roomId });
      const allowed = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request("https://codes/rate-limit", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ key: rateKey })
        })
      );
      if (!allowed.ok) return json({ error: "Too many registration attempts. Try again later." }, 429);
      const password = typeof body.password === "string" ? body.password : "";
      if (password.length < 4) return json({ error: "Password must contain at least 4 characters." }, 400);
      const code = randomCode();
      const record: CodeRecord = {
        roomId,
        wsUrl,
        passwordHash: await hashPassword(password, roomPasswordSalt(env, roomId)),
        expiresAt: Date.now() + expiresIn * 1000
      };
      const response = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request("https://codes/claim", {
          method: "POST",
          body: JSON.stringify({ code, record })
        })
      );
      if (!response.ok) return json({ error: "Could not create room code." }, 503);
      const token = await createSessionToken(
        { roomId, code, purpose: "resolve", exp: Math.floor(Date.now() / 1000) + 86400 },
        sessionSecret(env)
      );
      return json({ code, roomId, wsUrl, sessionToken: token });
    }

    if (url.pathname === "/resolve") {
      const code = typeof body.code === "string" ? body.code.trim() : "";
      if (!/^\d{5}$/.test(code)) return json({ error: "Invalid code." }, 400);
      const clientIp = clientAddress(request);
      const rateKey = buildRateLimitKey({ action: "resolve", clientIP: clientIp, code });
      const allowed = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request("https://codes/rate-limit", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ key: rateKey })
        })
      );
      if (!allowed.ok) return json({ error: "Too many lookup attempts. Try again later." }, 429);
      const response = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request(`https://codes/resolve?code=${encodeURIComponent(code)}`)
      );
      if (!response.ok) return json({ error: "Session not found or expired." }, 404);
      const record = await response.json() as CodeRecord;
      if (record.passwordHash) {
        const password = typeof body.password === "string" ? body.password : "";
        const validPassword = await verifyPassword(
          password,
          record.passwordHash,
          roomPasswordSalt(env, record.roomId)
        );
        if (!validPassword) return json({ error: "Room password is incorrect." }, 403);
      }

      const tokenSecret = sessionSecret(env);
      const token = await createSessionToken(
        { roomId: record.roomId, code, purpose: "resolve", exp: Math.floor(Date.now() / 1000) + 86400 },
        tokenSecret
      );
      return json({ roomId: record.roomId, wsUrl: record.wsUrl, sessionToken: token });
    }

    if (url.pathname === "/resolve-room") {
      if (!roomId) return json({ error: "roomId is required." }, 400);
      const password = typeof body.password === "string" ? body.password : "";
      const passwordHash = await hashPassword(password, roomPasswordSalt(env, roomId));
      const response = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request(`https://codes/resolve-room?roomId=${encodeURIComponent(roomId)}`, {
          method: "POST",
          body: JSON.stringify({ passwordHash })
        })
      );
      if (!response.ok) return json({ error: "Room not found or password is incorrect." }, 403);
      const resolved = await response.json() as { roomId?: string; wsUrl?: string };
      const tokenSecret = sessionSecret(env);
      const token = await createSessionToken(
        { roomId: resolved.roomId ?? roomId, code: "", purpose: "resolve", exp: Math.floor(Date.now() / 1000) + 86400 },
        tokenSecret
      );
      return json({ roomId: resolved.roomId ?? roomId, wsUrl: resolved.wsUrl ?? signalURL(request), sessionToken: token });
    }

    if (url.pathname === "/push/register") {
      const registration = normalizePushRegistration(body as Record<string, unknown>);
      if (!registration) {
        return json({ error: "Valid deviceToken and platform are required." }, 400);
      }

      const registryResponse = await env.CODES.get(env.CODES.idFromName("device-registry")).fetch(
        new Request("https://push/register", {
          method: "POST",
          body: JSON.stringify(registration)
        })
      );

      if (!registryResponse.ok) {
        return json({ error: "Could not store device registration." }, 503);
      }

      return json({ success: true, platform: registration.platform, roomId: registration.roomId ?? null });
    }

    if (url.pathname === "/push/send") {
      const payload = normalizePushNotification(body as Record<string, unknown>);
      if (!payload) {
        return json({ error: "Valid push payload is required." }, 400);
      }

      const registry = await env.CODES.get(env.CODES.idFromName("device-registry")).fetch(
        new Request(`https://push/lookup?deviceToken=${encodeURIComponent(payload.deviceToken)}`)
      );
      if (!registry.ok) {
        return json({ error: "No matching device registration found." }, 404);
      }

      const registration = await registry.json() as { deviceToken?: string; platform?: string; roomId?: string };
      const response = await fetch("https://api.push.apple.com/3/device/" + registration.deviceToken, {
        method: "POST",
        headers: {
          "apns-topic": "JaysApps.BlinkCast",
          "apns-push-type": "alert",
          "content-type": "application/json",
          "authorization": `bearer ${env.APNS_TOKEN ?? ""}`
        },
        body: JSON.stringify({ aps: payload.aps.alert })
      });

      if (!response.ok) {
        return json({ error: "Could not dispatch APNs notification." }, 503);
      }

      return json({ success: true, type: payload.type, deviceToken: payload.deviceToken });
    }

    return json({ error: "Not found." }, 404);
  }
};

export class CodeRegistry {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/rate-limit" && request.method === "POST") {
      const body = await readJSON(request);
      const key = typeof body.key === "string" ? body.key : "unknown";
      const bucket = `rate:${key}:${Math.floor(Date.now() / 60_000)}`;
      const count = await this.state.storage.get<number>(bucket) || 0;
      if (count >= 30) return new Response(null, { status: 429 });
      await this.state.storage.put(bucket, count + 1);
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/claim" && request.method === "POST") {
      const body = await readJSON(request);
      const code = typeof body.code === "string" ? body.code : "";
      const record = body.record as CodeRecord | undefined;
      if (!code || !record) return new Response(null, { status: 400 });
      const existing = await this.state.storage.get<CodeRecord>(`code:${code}`);
      if (existing && existing.expiresAt > Date.now()) return new Response(null, { status: 409 });
      await this.state.storage.put(`code:${code}`, record);
      return new Response(null, { status: 201 });
    }

    const code = url.searchParams.get("code");
    if (url.pathname === "/resolve" && code) {
      const record = await this.state.storage.get<CodeRecord>(`code:${code}`);
      return record && record.expiresAt > Date.now()
        ? Response.json(record)
        : new Response(null, { status: 404 });
    }

    if (url.pathname === "/resolve-room" && request.method === "POST") {
      const passwordHash = (await readJSON(request)).passwordHash;
      const entries = await this.state.storage.list<CodeRecord>({ prefix: "code:" });
      for (const record of entries.values()) {
        if (record.roomId === url.searchParams.get("roomId") && record.expiresAt > Date.now() && record.passwordHash === passwordHash) {
          return Response.json({ roomId: record.roomId, wsUrl: record.wsUrl });
        }
      }
      return new Response(null, { status: 404 });
    }

    if (url.pathname === "/record" && request.method === "POST") {
      const report = await readJSON(request) as DiagnosticsReport;
      const key = `report:${report.timestamp}:${report.clientId}`;
      const reports = await this.state.storage.list<DiagnosticsReport>({
        prefix: "report:",
        limit: 100,
        reverse: true
      });
      await this.state.storage.put(key, report);
      if (reports.size > 100) {
        const keysToDelete: string[] = [];
        let count = 0;
        for (const [k] of reports) {
          count += 1;
          if (count > 100) keysToDelete.push(k);
        }
        await this.state.storage.delete(keysToDelete);
      }
      return new Response(null, { status: 201 });
    }

    if (url.pathname === "/list" && request.method === "GET") {
      const reports = await this.state.storage.list<DiagnosticsReport>({
        prefix: "report:",
        limit: 100,
        reverse: true
      });
      const result: DiagnosticsReport[] = [];
      for (const [, report] of reports) {
        result.push(report);
      }
      return new Response(JSON.stringify(result), {
        headers: { "content-type": "application/json" }
      });
    }

    if (url.pathname === "/push/register" && request.method === "POST") {
      const body = await readJSON(request) as { deviceToken?: string; platform?: string; roomId?: string };
      const registration = normalizePushRegistration(body);
      if (!registration) {
        return new Response(null, { status: 400 });
      }

      const key = `push:${registration.platform}:${registration.deviceToken}`;
      await this.state.storage.put(key, {
        deviceToken: registration.deviceToken,
        platform: registration.platform,
        roomId: registration.roomId ?? null,
        updatedAt: Date.now()
      });

      return Response.json({ success: true });
    }

    if (url.pathname === "/push/lookup" && request.method === "GET") {
      const deviceToken = url.searchParams.get("deviceToken");
      if (!deviceToken) return new Response(null, { status: 400 });
      const key = `push:ios:${deviceToken}`;
      const registration = await this.state.storage.get<{ deviceToken: string; platform: string; roomId?: string | null }>(key);
      if (!registration) return new Response(null, { status: 404 });
      return Response.json(registration);
    }

    return new Response(null, { status: 404 });
  }
}

export class Room {
  constructor(private readonly state: DurableObjectState) {}

  private viewers: Map<string, ViewerInfo> = new Map();
  private viewerMetrics: Map<string, ViewerMetrics> = new Map();
  private requiresModeration = false;
  private hostActive = false;
  private sessionStartTime = 0;
  private peakViewerCount = 0;
  private sessionSecret = "blinkcast-default-secret";
  private maxViewerCount = 8;
  private heartbeatTimer: ReturnType<typeof setTimeout> | null = null;

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "WebSocket upgrade required." }, 426);
    }

    const requestSecret = request.headers.get("x-blinkcast-session-secret");
    if (requestSecret) this.sessionSecret = requestSecret;
    const configuredMaxViewers = Number.parseInt(request.headers.get("x-blinkcast-max-viewers") || "8", 10);
    if (Number.isFinite(configuredMaxViewers) && configuredMaxViewers > 0) {
      this.maxViewerCount = configuredMaxViewers;
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.state.acceptWebSocket(server);
    this.startHeartbeat();
    return new Response(null, { status: 101, webSocket: client });
  }

  private startHeartbeat(): void {
    if (this.heartbeatTimer) return;
    this.heartbeatTimer = setInterval(() => {
      this.state.getWebSockets().forEach((ws) => {
        try {
          ws.ping();
        } catch {
          // Socket may be closed
        }
      });
    }, 30000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  async webSocketMessage(webSocket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;
    let value: Record<string, unknown>;
    try {
      value = JSON.parse(message) as Record<string, unknown>;
    } catch {
      webSocket.send(JSON.stringify({ type: "error", message: "Invalid JSON." }));
      return;
    }

    if (value.type === "join") {
      await this.handleJoin(webSocket, value);
      return;
    }

    const sender = this.info(webSocket);
    if (!sender) {
      webSocket.send(JSON.stringify({ type: "error", message: "Join the room first." }));
      return;
    }

    if (value.type === "moderate" && sender.role === "host") {
      await this.handleModeration(webSocket, value);
      return;
    }

    if (value.type === "viewer-metrics" && sender.role === "viewer") {
      this.updateViewerMetrics(sender.clientId, value);
      return;
    }

    if (value.type === "analytics-request" && sender.role === "host") {
      this.sendRoomAnalyticsToHost(webSocket);
      return;
    }

    if (value.type === "broadcast-end" && sender.role === "host") {
      this.broadcast({ type: "broadcast-ended" });
      return;
    }

    if (value.type === "signal") {
      const data = value.data as Record<string, unknown> | undefined;
      if (!data || typeof data !== "object") return;
      const target = typeof data.to === "string" ? data.to : null;
      if (data.from !== sender.clientId) return;
      if (sender.role === "viewer" && this.viewers.get(sender.clientId)?.status !== "approved") {
        webSocket.send(JSON.stringify({ type: "error", message: "Viewer approval is required before streaming." }));
        return;
      }
      const destination = target
        ? this.findClient(target)
        : sender.role === "viewer"
          ? this.findRole("host")
          : null;
      if (destination) {
        try {
          destination.send(JSON.stringify({ type: "signal", data }));
        } catch {
          try { destination.close(1011, "Peer socket unavailable"); } catch { /* already closed */ }
        }
      }
    }
  }

  async webSocketClose(webSocket: WebSocket): Promise<void> {
    const sender = this.info(webSocket);
    if (sender?.role === "host") {
      this.broadcast({ type: "broadcast-ended" });
      this.hostActive = false;
    }
    if (sender?.role === "viewer") {
      this.viewers.delete(sender.clientId);
      this.viewerMetrics.delete(sender.clientId);
      this.broadcastViewerList();
      if (this.hostActive) {
        this.broadcastRoomAnalytics();
      }
    }
    // Stop heartbeat when no WebSockets remain
    if (this.state.getWebSockets().length === 0) {
      this.stopHeartbeat();
    }
  }

  async webSocketError(webSocket: WebSocket): Promise<void> {
    await this.webSocketClose(webSocket);
  }

  private async handleJoin(webSocket: WebSocket, value: Record<string, unknown>): Promise<void> {
    const role = value.role === "host" || value.role === "viewer" ? value.role : null;
    const roomId = normalizeRoomId(value.roomId);
    const clientId = typeof value.clientId === "string" ? value.clientId : null;
    const token = typeof value.sessionToken === "string" ? value.sessionToken : "";
    const code = typeof value.code === "string" ? value.code : "";
    const secret = this.sessionSecret;

    if (!role || !roomId || !clientId) {
      webSocket.send(JSON.stringify({ type: "error", message: "Invalid join message." }));
      webSocket.close(1008, "Invalid join message");
      return;
    }

    if (role === "viewer" || role === "host") {
      const authorized = await validateJoinAuthorization({ roomId, code, token, role }, secret);
      if (!authorized) {
        webSocket.send(JSON.stringify({ type: "error", message: "Unauthorized session join." }));
        webSocket.close(1008, "Unauthorized session join");
        return;
      }
    }

    const hasHost = this.findRole("host") !== null;
    const hostSocket = this.findRole("host");

    const clientInfo: ClientInfo = { role, roomId, clientId };
    webSocket.serializeAttachment(clientInfo);

    if (role === "viewer") {
      if (this.viewers.size >= this.maxViewerCount) {
        webSocket.send(JSON.stringify({ type: "error", message: "This room has reached its viewer limit." }));
        webSocket.close(1013, "Viewer limit reached");
        return;
      }
      const viewerStatus = hasHost && !this.requiresModeration ? "approved" : "pending";
      const viewerInfo: ViewerInfo = { ...clientInfo, status: viewerStatus, joinedAt: Date.now() };
      this.viewers.set(clientId, viewerInfo);
      this.viewerMetrics.set(clientId, {
        ...viewerInfo,
        bitrate: 0,
        packetLoss: 0,
        rtt: 0,
        networkQuality: "unknown",
        lastUpdate: Date.now()
      });

      this.peakViewerCount = Math.max(this.peakViewerCount, this.viewers.size);
      webSocket.send(JSON.stringify({ type: "joined", hostAvailable: hasHost, requiresModeration: this.requiresModeration }));

      if (hasHost && this.requiresModeration) {
        this.broadcastViewerList();
        hostSocket?.send(JSON.stringify({ type: "viewer-join-request", viewer: { clientId } }));
      } else if (hasHost) {
        this.broadcastViewerList();
      }
    } else {
      // Host connection
      this.requiresModeration = value.requiresApproval !== false;
      if (!this.requiresModeration) {
        for (const viewer of this.viewers.values()) {
          if (viewer.status !== "approved") {
            viewer.status = "approved";
            this.findClient(viewer.clientId)?.send(JSON.stringify({ type: "approval", status: "approved" }));
          }
        }
      }
      if (!this.sessionStartTime) {
        this.sessionStartTime = Date.now();
      }
      this.hostActive = true;
      webSocket.send(JSON.stringify({ type: "joined", hostAvailable: false, viewerCount: this.viewers.size, requiresModeration: this.requiresModeration }));
      this.broadcast({ type: "host-available" }, webSocket);
      this.broadcastViewerList();
      this.broadcastRoomAnalytics();
    }
  }

  private async handleModeration(webSocket: WebSocket, value: Record<string, unknown>): Promise<void> {
    const action = typeof value.action === "string" ? value.action : "";
    const clientId = typeof value.clientId === "string" ? value.clientId : "";

    if (!action || !clientId) return;

    const viewer = this.viewers.get(clientId);
    if (!viewer) return;

    if (action === "approve") {
      viewer.status = "approved";
      const viewerSocket = this.findClient(clientId);
      viewerSocket?.send(JSON.stringify({ type: "approval", status: "approved" }));
    } else if (action === "deny") {
      viewer.status = "denied";
      const viewerSocket = this.findClient(clientId);
      viewerSocket?.send(JSON.stringify({ type: "approval", status: "denied" }));
      try {
        viewerSocket?.close(1008, "Join request denied by host");
      } catch {
        /* already closed */
      }
      this.viewers.delete(clientId);
    } else if (action === "kick") {
      const viewerSocket = this.findClient(clientId);
      try {
        viewerSocket?.close(1008, "Kicked by host");
      } catch {
        /* already closed */
      }
      this.viewers.delete(clientId);
    }

    this.broadcastViewerList();
  }

  private broadcastViewerList(): void {
    const viewers = Array.from(this.viewers.values()).map((v) => ({
      clientId: v.clientId,
      status: v.status,
      joinedAt: v.joinedAt
    }));
    const host = this.findRole("host");
    host?.send(JSON.stringify({
      type: "viewer-list",
      viewers,
      count: viewers.length,
      requiresModeration: this.requiresModeration
    }));
  }

  private updateViewerMetrics(clientId: string, value: Record<string, unknown>): void {
    const existing = this.viewerMetrics.get(clientId);
    if (!existing) return;

    const updated: ViewerMetrics = {
      ...existing,
      bitrate: typeof value.bitrate === "number" ? value.bitrate : existing.bitrate,
      packetLoss: typeof value.packetLoss === "number" ? value.packetLoss : existing.packetLoss,
      rtt: typeof value.rtt === "number" ? value.rtt : existing.rtt,
      networkQuality: typeof value.networkQuality === "string" ? value.networkQuality : existing.networkQuality,
      lastUpdate: Date.now()
    };
    this.viewerMetrics.set(clientId, updated);
  }

  private broadcastRoomAnalytics(): void {
    const host = this.findRole("host");
    if (!host) return;

    const metrics = Array.from(this.viewerMetrics.values());
    const totalBitrate = metrics.reduce((sum, m) => sum + m.bitrate, 0);
    const avgRtt = metrics.length > 0
      ? Math.round(metrics.reduce((sum, m) => sum + m.rtt, 0) / metrics.length)
      : 0;
    const avgPacketLoss = metrics.length > 0
      ? metrics.reduce((sum, m) => sum + m.packetLoss, 0) / metrics.length
      : 0;

    const analytics: RoomAnalytics = {
      roomId: "",
      totalViewers: this.viewers.size,
      approvedViewers: Array.from(this.viewers.values()).filter((v) => v.status === "approved").length,
      pendingViewers: Array.from(this.viewers.values()).filter((v) => v.status === "pending").length,
      deniedViewers: Array.from(this.viewers.values()).filter((v) => v.status === "denied").length,
      totalBitrate,
      averageLatency: avgRtt,
      averagePacketLoss: avgPacketLoss,
      isHostActive: this.hostActive,
      sessionDuration: this.sessionStartTime > 0 ? Date.now() - this.sessionStartTime : 0,
      peakViewerCount: this.peakViewerCount
    };

    host.send(JSON.stringify({ type: "room-analytics", analytics }));
  }

  private sendRoomAnalyticsToHost(webSocket: WebSocket): void {
    const metrics = Array.from(this.viewerMetrics.values());
    const totalBitrate = metrics.reduce((sum, m) => sum + m.bitrate, 0);
    const avgRtt = metrics.length > 0
      ? Math.round(metrics.reduce((sum, m) => sum + m.rtt, 0) / metrics.length)
      : 0;
    const avgPacketLoss = metrics.length > 0
      ? metrics.reduce((sum, m) => sum + m.packetLoss, 0) / metrics.length
      : 0;

    const analytics: RoomAnalytics = {
      roomId: "",
      totalViewers: this.viewers.size,
      approvedViewers: Array.from(this.viewers.values()).filter((v) => v.status === "approved").length,
      pendingViewers: Array.from(this.viewers.values()).filter((v) => v.status === "pending").length,
      deniedViewers: Array.from(this.viewers.values()).filter((v) => v.status === "denied").length,
      totalBitrate,
      averageLatency: avgRtt,
      averagePacketLoss: avgPacketLoss,
      isHostActive: this.hostActive,
      sessionDuration: this.sessionStartTime > 0 ? Date.now() - this.sessionStartTime : 0,
      peakViewerCount: this.peakViewerCount
    };

    webSocket.send(JSON.stringify({ type: "room-analytics", analytics }));
  }

  private sockets(): WebSocket[] {
    return this.state.getWebSockets();
  }

  private info(webSocket: WebSocket): ClientInfo | null {
    return webSocket.deserializeAttachment() as ClientInfo | null;
  }

  private findClient(clientId: string): WebSocket | null {
    return this.sockets().find((socket) => this.info(socket)?.clientId === clientId) ?? null;
  }

  private findRole(role: Role): WebSocket | null {
    return this.sockets().find((socket) => this.info(socket)?.role === role) ?? null;
  }

  private broadcast(value: unknown, except?: WebSocket): void {
    const message = JSON.stringify(value);
    for (const socket of this.sockets()) {
      if (socket !== except) {
        try { socket.send(message); } catch { /* disconnected socket */ }
      }
    }
  }

  private broadcastToRole(role: Role, value: unknown): void {
    const message = JSON.stringify(value);
    for (const socket of this.sockets()) {
      const info = this.info(socket);
      if (info?.role === role) {
        try { socket.send(message); } catch { /* disconnected socket */ }
      }
    }
  }
}
