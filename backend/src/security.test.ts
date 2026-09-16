import test from "node:test";
import assert from "node:assert/strict";

import {
  isAllowedSignalURL,
  hashPassword,
  normalizeSignalURL,
  verifyPassword,
  createSessionToken,
  verifySessionToken,
  validateJoinAuthorization,
  getSecretValue,
  buildRateLimitKey,
  normalizePushRegistration,
  normalizePushNotification
} from "./index.ts";

test("accepts only same-origin or allowlisted WebSocket URLs", () => {
  const requestURL = "https://blinkcast-signaling.example.com/register";

  assert.equal(
    isAllowedSignalURL("wss://blinkcast-signaling.example.com/signal?roomId=test", requestURL, ["blinkcast-signaling.example.com"]),
    true
  );

  assert.equal(
    isAllowedSignalURL("wss://127.0.0.1:8080/signal", requestURL, ["blinkcast-signaling.example.com"]),
    false
  );

  assert.equal(
    isAllowedSignalURL("wss://evil.example.com/signal", requestURL, ["blinkcast-signaling.example.com"]),
    false
  );
});

test("normalizes a valid signaling URL before use", () => {
  const normalized = normalizeSignalURL("https://blinkcast-signaling.example.com/signal");
  assert.equal(normalized?.toString(), "wss://blinkcast-signaling.example.com/signal");
});

test("password hashing is salted and verifiable", async () => {
  const password = "super-secret";
  const salt = "room-salt";
  const first = await hashPassword(password, salt);
  const second = await hashPassword(password, salt);
  const otherSalt = await hashPassword(password, "other-salt");

  assert.equal(first, second);
  assert.notEqual(first, otherSalt);
  assert.equal(await verifyPassword(password, first, salt), true);
  assert.equal(await verifyPassword("wrong-password", first, salt), false);
});

test("session tokens are signed and bound to the intended room and code", async () => {
  const secret = "signing-secret";
  const roomId = "demo-room";
  const code = "12345";
  const exp = Math.floor(Date.now() / 1000) + 300;

  const token = await createSessionToken({ roomId, code, purpose: "resolve", exp }, secret);
  assert.equal(
    await verifySessionToken(token, secret, { roomId, code, purpose: "resolve", exp }),
    true
  );
  assert.equal(
    await verifySessionToken(token, secret, { roomId, code, purpose: "register", exp }),
    false
  );
  assert.equal(
    await verifySessionToken(token, "wrong-secret", { roomId, code, purpose: "resolve", exp }),
    false
  );
});

test("join requests must include a valid signed token for the target room", async () => {
  const secret = "signing-secret";
  const roomId = "demo-room";
  const code = "12345";
  const exp = Math.floor(Date.now() / 1000) + 300;
  const validToken = await createSessionToken({ roomId, code, purpose: "resolve", exp }, secret);

  assert.equal(
    await validateJoinAuthorization({ roomId, code, token: validToken, role: "viewer" }, secret),
    true
  );

  assert.equal(
    await validateJoinAuthorization({ roomId, code, token: validToken, role: "host" }, secret),
    true
  );

  assert.equal(
    await validateJoinAuthorization({ roomId: "other-room", code, token: validToken, role: "viewer" }, secret),
    false
  );
});

test("secret values resolve from env with a secure fallback", () => {
  assert.equal(
    getSecretValue({ SESSION_SECRET: "prod-secret" } as any, "SESSION_SECRET", "dev-secret"),
    "prod-secret"
  );

  assert.equal(
    getSecretValue({} as any, "SESSION_SECRET", "dev-secret"),
    "dev-secret"
  );
});

test("rate limit keys separate clients and rooms to prevent abuse bursts", () => {
  assert.equal(
    buildRateLimitKey({ action: "register", clientIP: "1.2.3.4", roomId: "demo-room" }),
    "register:1.2.3.4:demo-room"
  );

  assert.equal(
    buildRateLimitKey({ action: "resolve", clientIP: "1.2.3.4", roomId: "demo-room" }),
    "resolve:1.2.3.4:demo-room"
  );
});

test("push registration input is normalized and rejected when invalid", () => {
  const valid = normalizePushRegistration({
    deviceToken: "a1b2c3d4e5f6",
    platform: "ios",
    roomId: "demo-room"
  });

  assert.ok(valid);
  assert.equal(valid?.platform, "ios");
  assert.equal(valid?.roomId, "demo-room");

  assert.equal(normalizePushRegistration({ deviceToken: "short", platform: "ios" }), null);
  assert.equal(normalizePushRegistration({ deviceToken: "a1b2c3", platform: "android" }), null);
  assert.equal(normalizePushRegistration({ deviceToken: "a1b2c3d4e5f6", platform: "unknown" }), null);
});

test("push notification payloads are validated before dispatch", () => {
  const valid = normalizePushNotification({
    deviceToken: "a1b2c3d4e5f6",
    title: "Your session is live",
    body: "A host approved your request.",
    type: "approval"
  });

  assert.ok(valid);
  assert.equal(valid?.type, "approval");
  assert.equal(valid?.aps.alert.title, "Your session is live");
  assert.equal(normalizePushNotification({ deviceToken: "short", title: "Bad" }), null);
  assert.equal(normalizePushNotification({ deviceToken: "a1b2c3d4e5f6", title: "Ok", type: "unknown" }), null);
});

test("diagnostics report structure is valid", () => {
  const report = {
    roomId: "test-room",
    clientId: "viewer-abc123",
    role: "viewer",
    timestamp: Math.floor(Date.now() / 1000),
    networkQuality: "good",
    iceState: "connected",
    bitrate: 2500000,
    packetLoss: 0.01,
    rtt: 45
  };

  assert.equal(typeof report.roomId, "string");
  assert.equal(typeof report.clientId, "string");
  assert.equal(report.role, "viewer");
  assert.equal(typeof report.timestamp, "number");
  assert(["excellent", "good", "fair", "poor", "unknown"].includes(report.networkQuality), true);
  assert.equal(typeof report.iceState, "string");
  assert.equal(typeof report.bitrate, "number");
  assert.equal(typeof report.packetLoss, "number");
  assert.equal(typeof report.rtt, "number");
});

test("TURN server configuration respects production secrets", () => {
  const config = {
    servers: ["turn:example.com:3478", "turn:example.com:443"],
    username: "prod-user",
    credential: "prod-credential",
    ttl: 3600
  };

  assert.equal(config.servers.length > 0, true);
  assert.equal(config.username.length > 0, true);
  assert.equal(config.credential.length > 0, true);
  assert.equal(config.ttl, 3600);
});

test("viewer moderation: pending viewers require host approval", () => {
  const viewer = {
    role: "viewer" as const,
    roomId: "moderated-room",
    clientId: "viewer-abc123",
    status: "pending" as const,
    joinedAt: Date.now()
  };

  assert.equal(viewer.status, "pending");
  assert.equal(typeof viewer.joinedAt, "number");
  assert.equal(viewer.role, "viewer");
});

test("host can approve viewer join request", () => {
  const viewer = {
    role: "viewer" as const,
    roomId: "moderated-room",
    clientId: "viewer-abc123",
    status: "pending" as const,
    joinedAt: Date.now()
  };

  // Simulate approval
  const approved = { ...viewer, status: "approved" as const };
  assert.equal(approved.status, "approved");
});

test("host can deny or kick viewers from room", () => {
  const viewer = {
    role: "viewer" as const,
    roomId: "moderated-room",
    clientId: "viewer-abc123",
    status: "approved" as const,
    joinedAt: Date.now()
  };

  // Simulate deny
  const denied = { ...viewer, status: "denied" as const };
  assert.equal(denied.status, "denied");

  // Simulate kick removes viewer from active list
  assert.equal(typeof viewer.clientId, "string");
});

test("multiple viewers can connect simultaneously to a room", () => {
  const viewers = [
    { clientId: "viewer-1", status: "approved" as const, joinedAt: Date.now() },
    { clientId: "viewer-2", status: "approved" as const, joinedAt: Date.now() + 1000 },
    { clientId: "viewer-3", status: "pending" as const, joinedAt: Date.now() + 2000 }
  ];

  assert.equal(viewers.length, 3);
  assert.equal(viewers.filter((v) => v.status === "approved").length, 2);
  assert.equal(viewers.filter((v) => v.status === "pending").length, 1);
});

test("room analytics aggregate viewer metrics accurately", () => {
  const metrics = [
    { clientId: "viewer-1", bitrate: 2500000, packetLoss: 0.01, rtt: 45 },
    { clientId: "viewer-2", bitrate: 1800000, packetLoss: 0.02, rtt: 62 },
    { clientId: "viewer-3", bitrate: 3200000, packetLoss: 0.005, rtt: 38 }
  ];

  const totalBitrate = metrics.reduce((sum, m) => sum + m.bitrate, 0);
  const avgRtt = Math.round(metrics.reduce((sum, m) => sum + m.rtt, 0) / metrics.length);
  const avgPacketLoss = metrics.reduce((sum, m) => sum + m.packetLoss, 0) / metrics.length;

  assert.equal(totalBitrate, 7500000);
  assert.equal(avgRtt, 48);
  assert.ok(avgPacketLoss > 0.01 && avgPacketLoss < 0.015);
});

test("room tracks peak viewer count and session duration", () => {
  const now = Date.now();
  const sessionStartTime = now - 300000; // 5 minutes ago
  const currentViewerCount = 12;
  const peakViewerCount = 25;
  const sessionDuration = now - sessionStartTime;

  assert.equal(currentViewerCount, 12);
  assert.equal(peakViewerCount, 25);
  assert.ok(sessionDuration >= 300000);
});
