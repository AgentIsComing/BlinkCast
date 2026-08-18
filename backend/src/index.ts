export interface Env {
  ROOMS: DurableObjectNamespace;
  CODES: DurableObjectNamespace;
  ROOM_TTL_SECONDS: string;
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

function normalizeRoomId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const roomId = value.trim();
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

async function hashPassword(password: string): Promise<string> {
  const bytes = new TextEncoder().encode(password);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { headers: jsonHeaders });

    const url = new URL(request.url);

    if (url.pathname === "/signal") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return json({ error: "WebSocket upgrade required." }, 426);
      }

      const roomId = normalizeRoomId(url.searchParams.get("roomId"));
      if (!roomId) return json({ error: "roomId is required." }, 400);
      const id = env.ROOMS.idFromName(roomId);
      return env.ROOMS.get(id).fetch(request);
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
    const wsUrl = roomId ? roomSignalURL(requestedWsUrl, roomId) : requestedWsUrl;
    const expiresIn = ttl(env);

    if (url.pathname === "/register") {
      if (!roomId) return json({ error: "roomId is required." }, 400);
      const allowed = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request("https://codes/rate-limit", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ key: `register:${clientAddress(request)}` })
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
      return json({ code, roomId, wsUrl });
    }

    if (url.pathname === "/register-room") {
      if (!roomId) return json({ error: "roomId is required." }, 400);
      const allowed = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request("https://codes/rate-limit", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ key: `register:${clientAddress(request)}` })
        })
      );
      if (!allowed.ok) return json({ error: "Too many registration attempts. Try again later." }, 429);
      const password = typeof body.password === "string" ? body.password : "";
      if (password.length < 4) return json({ error: "Password must contain at least 4 characters." }, 400);
      const code = randomCode();
      const record: CodeRecord = {
        roomId,
        wsUrl,
        passwordHash: await hashPassword(password),
        expiresAt: Date.now() + expiresIn * 1000
      };
      const response = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request("https://codes/claim", {
          method: "POST",
          body: JSON.stringify({ code, record })
        })
      );
      if (!response.ok) return json({ error: "Could not create room code." }, 503);
      return json({ code, roomId, wsUrl });
    }

    if (url.pathname === "/resolve") {
      const code = typeof body.code === "string" ? body.code.trim() : "";
      if (!/^\d{5}$/.test(code)) return json({ error: "Invalid code." }, 400);
      const allowed = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request("https://codes/rate-limit", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ key: `resolve:${clientAddress(request)}` })
        })
      );
      if (!allowed.ok) return json({ error: "Too many lookup attempts. Try again later." }, 429);
      const response = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request(`https://codes/resolve?code=${encodeURIComponent(code)}`)
      );
      if (!response.ok) return json({ error: "Session not found or expired." }, 404);
      const record = await response.json() as CodeRecord;
      if (record.passwordHash) return json({ error: "This session requires a room password." }, 403);
      return json({ roomId: record.roomId, wsUrl: record.wsUrl });
    }

    if (url.pathname === "/resolve-room") {
      if (!roomId) return json({ error: "roomId is required." }, 400);
      const password = typeof body.password === "string" ? body.password : "";
      const response = await env.CODES.get(env.CODES.idFromName("registry")).fetch(
        new Request(`https://codes/resolve-room?roomId=${encodeURIComponent(roomId)}`, {
          method: "POST",
          body: JSON.stringify({ passwordHash: await hashPassword(password) })
        })
      );
      if (!response.ok) return json({ error: "Room not found or password is incorrect." }, 403);
      return json(await response.json());
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

    return new Response(null, { status: 404 });
  }
}

export class Room {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "WebSocket upgrade required." }, 426);
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.state.acceptWebSocket(server);
    return new Response(null, { status: 101, webSocket: client });
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

    if (value.type === "broadcast-end" && sender.role === "host") {
      this.broadcast({ type: "broadcast-ended" });
      return;
    }

    if (value.type === "signal") {
      const data = value.data as Record<string, unknown> | undefined;
      if (!data || typeof data !== "object") return;
      const target = typeof data.to === "string" ? data.to : null;
      if (data.from !== sender.clientId) return;
      const destination = target
        ? this.findClient(target)
        : null;
      if (destination) destination.send(JSON.stringify({ type: "signal", data }));
    }
  }

  async webSocketClose(webSocket: WebSocket): Promise<void> {
    const sender = this.info(webSocket);
    if (sender?.role === "host") this.broadcast({ type: "broadcast-ended" });
  }

  async webSocketError(webSocket: WebSocket): Promise<void> {
    await this.webSocketClose(webSocket);
  }

  private async handleJoin(webSocket: WebSocket, value: Record<string, unknown>): Promise<void> {
    const role = value.role === "host" || value.role === "viewer" ? value.role : null;
    const roomId = normalizeRoomId(value.roomId);
    const clientId = typeof value.clientId === "string" ? value.clientId : null;
    if (!role || !roomId || !clientId) {
      webSocket.send(JSON.stringify({ type: "error", message: "Invalid join message." }));
      webSocket.close(1008, "Invalid join message");
      return;
    }

    webSocket.serializeAttachment({ role, roomId, clientId } satisfies ClientInfo);
    const hasHost = this.findRole("host") !== null;
    if (role === "host" && hasHost) {
      webSocket.send(JSON.stringify({ type: "error", message: "A host is already connected." }));
      webSocket.close(1008, "Host already connected");
      return;
    }

    webSocket.send(JSON.stringify({ type: "joined", hostAvailable: role === "host" || hasHost }));
    if (role === "host") {
      this.broadcast({ type: "host-available" }, webSocket);
    } else if (hasHost) {
      const host = this.findRole("host");
      host?.send(JSON.stringify({ type: "viewer-joined", viewer: { clientId } }));
    }
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
}
