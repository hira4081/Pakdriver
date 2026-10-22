import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import { createApp } from "../src/app.js";
import { createPool, migrate } from "../src/db.js";

let db, sock, pool, server, base;
const PORT = 54329;

before(async () => {
  db = await PGlite.create();
  sock = new PGLiteSocketServer({ db, port: PORT, host: "127.0.0.1" });
  await sock.start();
  pool = createPool(`postgres://postgres:postgres@127.0.0.1:${PORT}/postgres`, { max: 1 });
  await migrate(pool);
  const verifyGoogle = async (t) => {
    if (!t.startsWith("good:")) throw new Error("bad");
    const [, sub, email] = t.split(":");
    return { sub, email, emailVerified: !t.includes("unverified"), name: sub };
  };
  const app = createApp({ pool, jwtSecret: "test-secret-test-secret", verifyGoogle });
  await new Promise((r) => (server = app.listen(0, r)));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server?.close();
  await pool?.end();
  await sock?.stop();
  await db?.close();
});

async function call(method, path, token, body) {
  const res = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}
const login = async (sub) => (await call("POST", "/auth/google", null, { idToken: `good:${sub}:${sub}@gmail.com` + "x".repeat(10) })).body.token;

const KHI = { label: "Clifton, Karachi", lat: 24.8138, lng: 67.03 };
const AIR = { label: "Jinnah Airport", lat: 24.9065, lng: 67.1608 };

test("auth: rejects bad / unverified tokens and missing bearer", async () => {
  assert.equal((await call("POST", "/auth/google", null, { idToken: "nope".repeat(8) })).status, 401);
  assert.equal((await call("POST", "/auth/google", null, { idToken: "good:u:u@x.com:unverified" + "x".repeat(10) })).status, 401);
  assert.equal((await call("GET", "/me")).status, 401);
  assert.equal((await call("GET", "/me", "garbage")).status, 401);
});

test("full ride: request -> bid -> accept -> trip -> complete -> rate -> wallet", async () => {
  const rider = await login("rider1");
  const driver = await login("driver1");

  // rider must save phone first
  assert.equal((await call("POST", "/rides", rider, { pickup: KHI, dropoff: AIR, vehicleType: "car", fare: 900 })).status, 400);
  assert.equal((await call("PUT", "/me", rider, { phone: "03001234567" })).status, 200);

  // driver needs vehicle before going online
  assert.equal((await call("PUT", "/me", driver, { phone: "03111234567", role: "driver" })).status, 400);
  const d = await call("PUT", "/me", driver, { phone: "03111234567", role: "driver", vehicleType: "car", vehiclePlate: "abc-123", vehicleMake: "Suzuki", vehicleModel: "Cultus", vehicleColor: "White" });
  assert.equal(d.status, 200);
  assert.equal(d.body.vehicle.plate, "ABC-123");
  assert.equal((await call("POST", "/me/online", driver, { online: true, lat: 24.82, lng: 67.04 })).status, 200);

  const est = await call("POST", "/estimate", rider, { pickup: KHI, dropoff: AIR, vehicleType: "car" });
  assert.ok(est.body.suggestedFare >= 200 && est.body.distanceKm > 10);

  const created = await call("POST", "/rides", rider, { pickup: KHI, dropoff: AIR, vehicleType: "car", fare: 900 });
  assert.equal(created.status, 200);
  const rideId = created.body.id;
  assert.equal((await call("POST", "/rides", rider, { pickup: KHI, dropoff: AIR, vehicleType: "car", fare: 900 })).status, 409);

  // driver sees it (no bots), bids
  let b = (await call("GET", "/board", driver)).body;
  assert.equal(b.nearby.length, 1);
  assert.equal(b.nearby[0].id, rideId);
  assert.equal((await call("POST", `/rides/${rideId}/bids`, driver, { fare: 850 })).status, 200);
  assert.equal((await call("POST", `/rides/${rideId}/bids`, driver, { fare: 800 })).status, 200); // re-bid updates

  b = (await call("GET", "/board", rider)).body;
  assert.equal(b.bids.length, 1);
  assert.equal(b.bids[0].fare, 800);
  assert.equal(b.ride.driver, null);

  // a different vehicle type never sees it
  const bike = await login("bike1");
  await call("PUT", "/me", bike, { phone: "03221234567", role: "driver", vehicleType: "bike", vehiclePlate: "KHI-1" });
  await call("POST", "/me/online", bike, { online: true, lat: 24.82, lng: 67.04 });
  assert.equal((await call("GET", "/board", bike)).body.nearby.length, 0);
  assert.equal((await call("POST", `/rides/${rideId}/bids`, bike, { fare: 500 })).status, 403);

  // rider cannot accept someone else's / bogus bid; accepts the real one
  assert.equal((await call("POST", `/rides/${rideId}/accept`, rider, { bidId: 99999 })).status, 409);
  const acc = await call("POST", `/rides/${rideId}/accept`, rider, { bidId: b.bids[0].id });
  assert.equal(acc.status, 200);
  assert.equal(acc.body.status, "matched");
  assert.equal(acc.body.acceptedFare, 800);
  assert.equal(acc.body.driver.phone, "03111234567");
  assert.equal((await call("POST", `/rides/${rideId}/accept`, rider, { bidId: b.bids[0].id })).status, 409);

  // only the driver can advance, and must be near pickup to start
  assert.equal((await call("POST", `/rides/${rideId}/advance`, rider)).status, 404);
  assert.equal((await call("POST", `/rides/${rideId}/advance`, driver)).body.status, "arriving");
  assert.equal((await call("POST", `/rides/${rideId}/advance`, driver)).body.status, "arrived");
  await call("POST", "/me/location", driver, { lat: 25.5, lng: 68 });
  assert.equal((await call("POST", `/rides/${rideId}/advance`, driver)).status, 409);
  await call("POST", "/me/location", driver, { lat: KHI.lat, lng: KHI.lng });
  assert.equal((await call("POST", `/rides/${rideId}/advance`, driver)).body.status, "in_trip");

  // rider sees live driver location during trip
  assert.equal((await call("GET", "/board", rider)).body.ride.driver.lat, KHI.lat);
  assert.equal((await call("POST", `/rides/${rideId}/cancel`, rider)).status, 409); // not during trip

  assert.equal((await call("POST", `/rides/${rideId}/advance`, driver)).body.status, "completed");
  assert.equal((await call("POST", `/rides/${rideId}/advance`, driver)).status, 409);

  // ratings, once each
  assert.equal((await call("POST", `/rides/${rideId}/rate`, rider, { stars: 5 })).status, 200);
  assert.equal((await call("POST", `/rides/${rideId}/rate`, rider, { stars: 1 })).status, 409);
  assert.equal((await call("POST", `/rides/${rideId}/rate`, driver, { stars: 4 })).status, 200);

  const db1 = (await call("GET", "/board", driver)).body;
  assert.equal(db1.wallet, 800);
  assert.equal(db1.me.rating, 5);
  assert.equal(db1.me.tripsCount, 1);
  assert.equal(db1.ride, null);
  assert.equal(db1.trips[0].fare, 800);
  assert.equal((await call("GET", "/board", rider)).body.me.tripsCount, 1);
});

test("rider cancel, driver back-out reopens, and expiry", async () => {
  const rider = await login("rider2");
  const driver = await login("driver2");
  await call("PUT", "/me", rider, { phone: "03001230000" });
  await call("PUT", "/me", driver, { phone: "03111230000", role: "driver", vehicleType: "car", vehiclePlate: "XYZ-9" });
  await call("POST", "/me/online", driver, { online: true, lat: 24.82, lng: 67.04 });

  let r = (await call("POST", "/rides", rider, { pickup: KHI, dropoff: AIR, vehicleType: "car", fare: 700 })).body;
  assert.equal((await call("PUT", `/rides/${r.id}/fare`, rider, { fare: 800 })).body.offeredFare, 800);
  await call("POST", `/rides/${r.id}/bids`, driver, { fare: 800 });
  const bidId = (await call("GET", "/board", rider)).body.bids[0].id;
  await call("POST", `/rides/${r.id}/accept`, rider, { bidId });

  // driver backs out -> back to open with no driver
  assert.equal((await call("POST", `/rides/${r.id}/cancel`, driver)).status, 200);
  let b = (await call("GET", "/board", rider)).body;
  assert.equal(b.ride.status, "open");
  assert.equal(b.ride.driver, null);
  assert.equal(b.bids.length, 0);

  // rider cancels
  assert.equal((await call("POST", `/rides/${r.id}/cancel`, rider)).status, 200);
  b = (await call("GET", "/board", rider)).body;
  assert.equal(b.ride, null);
  assert.equal(b.trips[0].status, "cancelled");

  // expiry
  r = (await call("POST", "/rides", rider, { pickup: KHI, dropoff: AIR, vehicleType: "car", fare: 700 })).body;
  await pool.query("update rides set created_at = now() - interval '30 minutes' where id = $1", [r.id]);
  assert.equal((await call("GET", "/board", rider)).body.ride, null);
});

test("distance: real road km from the app is used only when plausible", async () => {
  const t = await login("km1");
  await call("PUT", "/me", t, { phone: "03001230001" });
  const base = { pickup: KHI, dropoff: AIR, vehicleType: "car" };
  const fallback = (await call("POST", "/estimate", t, base)).body.distanceKm;
  assert.equal((await call("POST", "/estimate", t, { ...base, routeKm: 22.4 })).body.distanceKm, 22.4);
  assert.equal((await call("POST", "/estimate", t, { ...base, routeKm: 1 })).body.distanceKm, fallback); // too short
  assert.equal((await call("POST", "/estimate", t, { ...base, routeKm: 900 })).body.distanceKm, fallback); // too long
  const r = await call("POST", "/rides", t, { pickup: KHI, dropoff: AIR, vehicleType: "car", fare: 800, routeKm: 22.4 });
  assert.equal(r.body.distanceKm, 22.4);
  await call("POST", `/rides/${r.body.id}/cancel`, t);
});

test("validation: bad payloads are rejected cleanly", async () => {
  const t = await login("val1");
  assert.equal((await call("PUT", "/me", t, { phone: "abc" })).status, 400);
  assert.equal((await call("POST", "/me/online", t, { online: true, lat: 1, lng: 1 })).status, 403); // not a driver
  assert.equal((await call("POST", "/rides", t, { pickup: KHI })).status, 400);
  assert.equal((await call("POST", "/rides/9999/cancel", t)).status, 404);
});
