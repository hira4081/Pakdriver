import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import jwt from "jsonwebtoken";
import { z } from "zod";
import { OAuth2Client } from "google-auth-library";
import { withTx } from "./db.js";
import { etaMinutes, haversineKm, roadKm, suggestFare } from "./geo.js";

const VEHICLES = ["bike", "rickshaw", "car"];
const OPEN_TTL_MIN = 20; // open requests expire after this
const ONLINE_TTL_MIN = 5; // driver must ping location within this
const NEARBY_KM = 15;
const ACTIVE = ["open", "matched", "arriving", "arrived", "in_trip"];
const NEXT = { matched: "arriving", arriving: "arrived", arrived: "in_trip", in_trip: "completed" };

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
const bad = (m) => new HttpError(400, m);
const forbidden = (m) => new HttpError(403, m);
const notFound = (m) => new HttpError(404, m);
const conflict = (m) => new HttpError(409, m);

const iso = (v) => (v ? new Date(v).toISOString() : null);

/** Default verifier: real Google ID-token check. */
export function googleVerifier(clientIds) {
  const client = new OAuth2Client();
  return async (idToken) => {
    const ticket = await client.verifyIdToken({ idToken, audience: clientIds });
    const p = ticket.getPayload();
    if (!p?.sub || !p.email) throw new Error("bad token");
    return { sub: p.sub, email: p.email, emailVerified: !!p.email_verified, name: p.name, picture: p.picture };
  };
}

const place = z.object({
  label: z.string().trim().min(2).max(200),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});
const coords = z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) });

const schemas = {
  google: z.object({ idToken: z.string().min(20) }),
  profile: z.object({
    name: z.string().trim().min(2).max(60).optional(),
    phone: z.string().trim().regex(/^\+?[0-9]{10,14}$/, "Valid phone number likho").optional(),
    role: z.enum(["rider", "driver"]).optional(),
    vehicleType: z.enum(VEHICLES).optional(),
    vehicleMake: z.string().trim().max(40).optional(),
    vehicleModel: z.string().trim().max(40).optional(),
    vehicleColor: z.string().trim().max(30).optional(),
    vehiclePlate: z.string().trim().min(3).max(15).optional(),
  }),
  online: z.object({ online: z.boolean(), lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) }),
  createRide: z.object({
    pickup: place,
    dropoff: place,
    vehicleType: z.enum(VEHICLES),
    fare: z.number().int().min(50).max(100000),
  }),
  estimate: z.object({ pickup: coords, dropoff: coords, vehicleType: z.enum(VEHICLES) }),
  fare: z.object({ fare: z.number().int().min(50).max(100000) }),
  bid: z.object({ fare: z.number().int().min(50).max(100000) }),
  accept: z.object({ bidId: z.number().int() }),
  rate: z.object({ stars: z.number().int().min(1).max(5) }),
};

function parse(schema, body) {
  const r = schema.safeParse(body ?? {});
  if (!r.success) throw bad(r.error.issues[0]?.message ?? "Invalid input");
  return r.data;
}

/* ---------- mappers ---------- */

function mapMe(u) {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    picture: u.picture,
    phone: u.phone,
    role: u.role,
    rating: u.rating_count ? Math.round((u.rating_sum / u.rating_count) * 10) / 10 : null,
    ratingCount: u.rating_count,
    tripsCount: u.trips_count,
    vehicle: u.vehicle_type
      ? {
          type: u.vehicle_type,
          make: u.vehicle_make,
          model: u.vehicle_model,
          color: u.vehicle_color,
          plate: u.vehicle_plate,
        }
      : null,
    isOnline: u.is_online,
    needsSetup: !u.phone,
  };
}

const RIDE_SQL = `
  select r.*,
    p.name as p_name, p.phone as p_phone, p.rating_sum as p_rs, p.rating_count as p_rc,
    d.name as d_name, d.phone as d_phone, d.rating_sum as d_rs, d.rating_count as d_rc,
    d.trips_count as d_trips, d.vehicle_type as d_vt, d.vehicle_make as d_vmake,
    d.vehicle_model as d_vmodel, d.vehicle_color as d_vcolor, d.vehicle_plate as d_vplate,
    d.lat as d_lat, d.lng as d_lng
  from rides r
  join users p on p.id = r.passenger_id
  left join users d on d.id = r.driver_id
`;

const avg = (s, c) => (c ? Math.round((s / c) * 10) / 10 : null);

function mapRide(r, viewerId) {
  const matched = ["matched", "arriving", "arrived", "in_trip", "completed"].includes(r.status);
  const live = ["matched", "arriving", "arrived", "in_trip"].includes(r.status);
  const mine = r.passenger_id === viewerId ? "rider" : "driver";
  return {
    id: r.id,
    status: r.status,
    myRole: mine,
    vehicleType: r.vehicle_type,
    pickup: { label: r.pickup_label, lat: r.pickup_lat, lng: r.pickup_lng },
    dropoff: { label: r.dropoff_label, lat: r.dropoff_lat, lng: r.dropoff_lng },
    distanceKm: r.distance_km,
    offeredFare: r.offered_fare,
    acceptedFare: r.accepted_fare,
    createdAt: iso(r.created_at),
    matchedAt: iso(r.matched_at),
    startedAt: iso(r.started_at),
    completedAt: iso(r.completed_at),
    cancelledBy: r.cancelled_by,
    myRating: mine === "rider" ? r.driver_rating : r.passenger_rating,
    passenger: {
      id: r.passenger_id,
      name: r.p_name,
      rating: avg(r.p_rs, r.p_rc),
      phone: live ? r.p_phone : null,
    },
    driver:
      matched && r.driver_id
        ? {
            id: r.driver_id,
            name: r.d_name,
            rating: avg(r.d_rs, r.d_rc),
            trips: r.d_trips,
            phone: live ? r.d_phone : null,
            lat: live ? r.d_lat : null,
            lng: live ? r.d_lng : null,
            vehicle: {
              type: r.d_vt,
              make: r.d_vmake,
              model: r.d_vmodel,
              color: r.d_vcolor,
              plate: r.d_vplate,
            },
          }
        : null,
  };
}

/* ---------- app ---------- */

export function createApp({ pool, jwtSecret, verifyGoogle, corsOrigin = "*" }) {
  if (!jwtSecret || jwtSecret.length < 16) throw new Error("JWT_SECRET must be at least 16 chars");
  const app = express();
  app.set("trust proxy", 1);
  app.use(helmet());
  app.use(cors({ origin: corsOrigin }));
  app.use(express.json({ limit: "50kb" }));

  const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res)).then((v) => v !== undefined && res.json(v), next);

  app.get("/health", wrap(async () => {
    await pool.query("select 1");
    return { ok: true };
  }));

  /* ---- auth ---- */
  const authLimiter = rateLimit({ windowMs: 60_000, limit: 20, standardHeaders: true, legacyHeaders: false });

  app.post("/auth/google", authLimiter, wrap(async (req) => {
    const { idToken } = parse(schemas.google, req.body);
    let g;
    try {
      g = await verifyGoogle(idToken);
    } catch {
      throw new HttpError(401, "Google sign-in verify nahi hua");
    }
    if (!g.emailVerified) throw new HttpError(401, "Google email verified nahi hai");
    const { rows } = await pool.query(
      `insert into users (google_sub, email, name, picture)
       values ($1,$2,$3,$4)
       on conflict (google_sub) do update set email = excluded.email, picture = excluded.picture
       returning *`,
      [g.sub, g.email, (g.name || g.email.split("@")[0]).slice(0, 60), g.picture ?? null],
    );
    const token = jwt.sign({}, jwtSecret, { subject: String(rows[0].id), expiresIn: "30d" });
    return { token, user: mapMe(rows[0]) };
  }));

  const auth = wrap2(async (req) => {
    const h = req.headers.authorization ?? "";
    const m = /^Bearer (.+)$/.exec(h);
    if (!m) throw new HttpError(401, "Login zaroori hai");
    let id;
    try {
      id = Number(jwt.verify(m[1], jwtSecret).sub);
    } catch {
      throw new HttpError(401, "Session expire ho gaya, dobara login karo");
    }
    const { rows } = await pool.query("select * from users where id = $1", [id]);
    if (!rows[0]) throw new HttpError(401, "Account nahi mila");
    req.user = rows[0];
  });
  function wrap2(fn) {
    return (req, res, next) => Promise.resolve(fn(req, res)).then(() => next(), next);
  }
  app.use(auth);

  /* ---- profile ---- */
  app.get("/me", wrap(async (req) => mapMe(req.user)));

  app.put("/me", wrap(async (req) => {
    const b = parse(schemas.profile, req.body);
    const u = req.user;
    if (b.role === "driver" && u.role !== "driver") {
      const type = b.vehicleType ?? u.vehicle_type;
      const plate = b.vehiclePlate ?? u.vehicle_plate;
      if (!type || !plate) throw bad("Driver banne ke liye vehicle type aur number plate likho");
    }
    if (b.role === "rider" && u.is_online) throw conflict("Pehle offline ho jao");
    const { rows } = await pool.query(
      `update users set
         name = coalesce($2, name), phone = coalesce($3, phone), role = coalesce($4, role),
         vehicle_type = coalesce($5, vehicle_type), vehicle_make = coalesce($6, vehicle_make),
         vehicle_model = coalesce($7, vehicle_model), vehicle_color = coalesce($8, vehicle_color),
         vehicle_plate = coalesce($9, vehicle_plate)
       where id = $1 returning *`,
      [u.id, b.name, b.phone, b.role, b.vehicleType, b.vehicleMake, b.vehicleModel, b.vehicleColor, b.vehiclePlate?.toUpperCase()],
    );
    return mapMe(rows[0]);
  }));

  app.post("/me/online", wrap(async (req) => {
    const b = parse(schemas.online, req.body);
    const u = req.user;
    if (u.role !== "driver") throw forbidden("Sirf driver online ho sakta hai");
    if (b.online) {
      if (!u.phone || !u.vehicle_type || !u.vehicle_plate) throw bad("Pehle profile aur vehicle poora karo");
    }
    const { rows } = await pool.query(
      "update users set is_online = $2, lat = $3, lng = $4, location_at = now() where id = $1 returning *",
      [u.id, b.online, b.lat, b.lng],
    );
    return mapMe(rows[0]);
  }));

  app.post("/me/location", wrap(async (req) => {
    const b = parse(coords, req.body);
    await pool.query("update users set lat = $2, lng = $3, location_at = now() where id = $1", [req.user.id, b.lat, b.lng]);
    return { ok: true };
  }));

  /* ---- fare estimate ---- */
  app.post("/estimate", wrap(async (req) => {
    const b = parse(schemas.estimate, req.body);
    const km = roadKm(b.pickup, b.dropoff);
    return { distanceKm: km, suggestedFare: suggestFare(b.vehicleType, km) };
  }));

  /* ---- board (single poll endpoint) ---- */
  app.get("/board", wrap(async (req) => {
    await pool.query(
      `update rides set status = 'cancelled', cancelled_by = 'system', cancelled_at = now()
       where status = 'open' and created_at < now() - make_interval(mins => $1)`,
      [OPEN_TTL_MIN],
    );
    const uid = req.user.id;
    const me = (await pool.query("select * from users where id = $1", [uid])).rows[0];

    const ride = (
      await pool.query(
        `${RIDE_SQL}
         where (r.passenger_id = $1 or r.driver_id = $1)
           and (r.status in ('open','matched','arriving','arrived','in_trip')
                or (r.status = 'completed' and r.completed_at > now() - interval '60 minutes'
                    and ((r.passenger_id = $1 and r.driver_rating is null)
                      or (r.driver_id = $1 and r.passenger_rating is null))))
         order by r.created_at desc limit 1`,
        [uid],
      )
    ).rows[0];

    let bids = [];
    if (ride && ride.passenger_id === uid && ride.status === "open") {
      bids = (
        await pool.query(
          `select b.id, b.fare, b.eta_minutes, b.created_at, u.id as driver_id, u.name, u.rating_sum, u.rating_count,
                  u.trips_count, u.vehicle_type, u.vehicle_make, u.vehicle_model, u.vehicle_color, u.vehicle_plate
           from bids b join users u on u.id = b.driver_id
           where b.ride_id = $1 and b.status = 'pending'
           order by b.fare asc, b.created_at asc`,
          [ride.id],
        )
      ).rows.map((b) => ({
        id: b.id,
        fare: b.fare,
        etaMinutes: b.eta_minutes,
        createdAt: iso(b.created_at),
        driver: {
          id: b.driver_id,
          name: b.name,
          rating: avg(b.rating_sum, b.rating_count),
          trips: b.trips_count,
          vehicle: { type: b.vehicle_type, make: b.vehicle_make, model: b.vehicle_model, color: b.vehicle_color, plate: b.vehicle_plate },
        },
      }));
    }

    let nearby = [];
    if (me.role === "driver" && me.is_online && !ride && me.lat != null) {
      const rows = (
        await pool.query(
          `select r.*, p.name as p_name, p.rating_sum as p_rs, p.rating_count as p_rc,
                  b.fare as my_bid
           from rides r
           join users p on p.id = r.passenger_id
           left join bids b on b.ride_id = r.id and b.driver_id = $1
           where r.status = 'open' and r.passenger_id <> $1 and r.vehicle_type = $2
             and r.created_at > now() - make_interval(mins => $3)
           order by r.created_at desc limit 60`,
          [uid, me.vehicle_type, OPEN_TTL_MIN],
        )
      ).rows;
      nearby = rows
        .map((r) => ({
          id: r.id,
          passengerName: r.p_name,
          passengerRating: avg(r.p_rs, r.p_rc),
          pickup: { label: r.pickup_label, lat: r.pickup_lat, lng: r.pickup_lng },
          dropoff: { label: r.dropoff_label, lat: r.dropoff_lat, lng: r.dropoff_lng },
          distanceKm: r.distance_km,
          offeredFare: r.offered_fare,
          createdAt: iso(r.created_at),
          myBid: r.my_bid,
          pickupAwayKm: Math.round(haversineKm({ lat: me.lat, lng: me.lng }, { lat: r.pickup_lat, lng: r.pickup_lng }) * 10) / 10,
        }))
        .filter((r) => r.pickupAwayKm <= NEARBY_KM)
        .sort((a, b) => a.pickupAwayKm - b.pickupAwayKm)
        .slice(0, 20);
    }

    const wallet = (await pool.query("select coalesce(sum(amount),0)::int as t from wallet_tx where user_id = $1", [uid])).rows[0].t;
    const trips = (
      await pool.query(
        `select r.id, r.status, r.pickup_label, r.dropoff_label, r.offered_fare, r.accepted_fare, r.created_at,
                r.completed_at, r.passenger_id, p.name as p_name, d.name as d_name
         from rides r join users p on p.id = r.passenger_id left join users d on d.id = r.driver_id
         where (r.passenger_id = $1 or r.driver_id = $1) and r.status in ('completed','cancelled')
         order by r.created_at desc limit 20`,
        [uid],
      )
    ).rows.map((r) => ({
      id: r.id,
      status: r.status,
      pickup: r.pickup_label,
      dropoff: r.dropoff_label,
      fare: r.accepted_fare ?? r.offered_fare,
      role: r.passenger_id === uid ? "rider" : "driver",
      counterpart: r.passenger_id === uid ? (r.d_name ?? "—") : r.p_name,
      createdAt: iso(r.created_at),
      completedAt: iso(r.completed_at),
    }));

    return { me: mapMe(me), ride: ride ? mapRide(ride, uid) : null, bids, nearby, wallet, trips };
  }));

  /* ---- rides ---- */
  async function loadRide(db, id, viewerId) {
    const r = (await db.query(`${RIDE_SQL} where r.id = $1`, [id])).rows[0];
    if (!r) throw notFound("Ride nahi mili");
    return mapRide(r, viewerId);
  }

  app.post("/rides", wrap(async (req) => {
    const b = parse(schemas.createRide, req.body);
    const u = req.user;
    if (!u.phone) throw bad("Pehle apna phone number save karo");
    const km = roadKm(b.pickup, b.dropoff);
    if (km < 0.3) throw bad("Pickup aur dropoff bohat qareeb hain");
    if (km > 800) throw bad("Distance bohat zyada hai");
    const id = await withTx(pool, async (c) => {
      const active = await c.query(
        "select 1 from rides where (passenger_id = $1 or driver_id = $1) and status in ('open','matched','arriving','arrived','in_trip')",
        [u.id],
      );
      if (active.rowCount) throw conflict("Aap ki pehle se ek active ride hai");
      const { rows } = await c.query(
        `insert into rides (passenger_id, vehicle_type, pickup_label, pickup_lat, pickup_lng,
           dropoff_label, dropoff_lat, dropoff_lng, distance_km, offered_fare)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) returning id`,
        [u.id, b.vehicleType, b.pickup.label, b.pickup.lat, b.pickup.lng, b.dropoff.label, b.dropoff.lat, b.dropoff.lng, km, b.fare],
      );
      return rows[0].id;
    });
    return loadRide(pool, id, u.id);
  }));

  /** Rider changes the offered fare while the ride is still open. Old bids are kept. */
  app.put("/rides/:id/fare", wrap(async (req) => {
    const { fare } = parse(schemas.fare, req.body);
    const id = Number(req.params.id);
    const r = await pool.query(
      "update rides set offered_fare = $3 where id = $1 and passenger_id = $2 and status = 'open' returning id",
      [id, req.user.id, fare],
    );
    if (!r.rowCount) throw conflict("Ab fare change nahi ho sakta");
    return loadRide(pool, id, req.user.id);
  }));

  app.post("/rides/:id/cancel", wrap(async (req) => {
    const id = Number(req.params.id);
    const uid = req.user.id;
    await withTx(pool, async (c) => {
      const r = (await c.query("select * from rides where id = $1 for update", [id])).rows[0];
      if (!r) throw notFound("Ride nahi mili");
      const isRider = r.passenger_id === uid;
      const isDriver = r.driver_id === uid;
      if (!isRider && !isDriver) throw forbidden("Ye aap ki ride nahi hai");
      if (!["open", "matched", "arriving", "arrived"].includes(r.status)) throw conflict("Ye ride ab cancel nahi ho sakti");
      if (isDriver && r.status !== "open") {
        // driver backs out: ride goes back to the board
        await c.query("update bids set status = 'rejected' where ride_id = $1 and driver_id = $2", [id, uid]);
        await c.query(
          "update rides set status = 'open', driver_id = null, accepted_fare = null, matched_at = null, arrived_at = null where id = $1",
          [id],
        );
      } else {
        await c.query("update rides set status = 'cancelled', cancelled_by = 'rider', cancelled_at = now() where id = $1", [id]);
      }
    });
    return { ok: true };
  }));

  app.post("/rides/:id/bids", wrap(async (req) => {
    const { fare } = parse(schemas.bid, req.body);
    const id = Number(req.params.id);
    const u = req.user;
    if (u.role !== "driver" || !u.is_online || u.lat == null) throw forbidden("Bid ke liye driver online hona chahiye");
    const ride = (await pool.query("select * from rides where id = $1", [id])).rows[0];
    if (!ride) throw notFound("Ride nahi mili");
    if (ride.status !== "open") throw conflict("Ye ride ab open nahi hai");
    if (ride.passenger_id === u.id) throw forbidden("Apni ride par bid nahi kar sakte");
    if (ride.vehicle_type !== u.vehicle_type) throw forbidden("Ye ride aap ki gaari ke liye nahi hai");
    const busy = await pool.query(
      "select 1 from rides where driver_id = $1 and status in ('matched','arriving','arrived','in_trip')",
      [u.id],
    );
    if (busy.rowCount) throw conflict("Aap pehle se ek ride mein hain");
    const eta = etaMinutes(roadKm({ lat: u.lat, lng: u.lng }, { lat: ride.pickup_lat, lng: ride.pickup_lng }));
    await pool.query(
      `insert into bids (ride_id, driver_id, fare, eta_minutes) values ($1,$2,$3,$4)
       on conflict (ride_id, driver_id) do update set fare = excluded.fare, eta_minutes = excluded.eta_minutes, status = 'pending', created_at = now()`,
      [id, u.id, fare, eta],
    );
    return { ok: true, etaMinutes: eta };
  }));

  app.post("/rides/:id/accept", wrap(async (req) => {
    const { bidId } = parse(schemas.accept, req.body);
    const id = Number(req.params.id);
    const uid = req.user.id;
    await withTx(pool, async (c) => {
      const r = (await c.query("select * from rides where id = $1 for update", [id])).rows[0];
      if (!r || r.passenger_id !== uid) throw notFound("Ride nahi mili");
      if (r.status !== "open") throw conflict("Ye ride ab open nahi hai");
      const bid = (await c.query("select * from bids where id = $1 and ride_id = $2 and status = 'pending' for update", [bidId, id])).rows[0];
      if (!bid) throw conflict("Ye bid ab available nahi hai");
      const busy = await c.query(
        "select 1 from rides where driver_id = $1 and status in ('matched','arriving','arrived','in_trip')",
        [bid.driver_id],
      );
      if (busy.rowCount) throw conflict("Ye driver ab kisi aur ride mein hai");
      await c.query("update bids set status = case when id = $2 then 'accepted' else 'rejected' end where ride_id = $1", [id, bidId]);
      await c.query(
        "update rides set status = 'matched', driver_id = $2, accepted_fare = $3, matched_at = now() where id = $1",
        [id, bid.driver_id, bid.fare],
      );
      // driver's other pending bids are no longer valid
      await c.query("update bids set status = 'rejected' where driver_id = $1 and status = 'pending' and ride_id <> $2", [bid.driver_id, id]);
    });
    return loadRide(pool, id, uid);
  }));

  app.post("/rides/:id/advance", wrap(async (req) => {
    const id = Number(req.params.id);
    const uid = req.user.id;
    await withTx(pool, async (c) => {
      const r = (await c.query("select * from rides where id = $1 for update", [id])).rows[0];
      if (!r || r.driver_id !== uid) throw notFound("Ride nahi mili");
      const next = NEXT[r.status];
      if (!next) throw conflict("Ride aage nahi barh sakti");
      if (next === "in_trip") {
        const d = (await c.query("select lat, lng from users where id = $1", [uid])).rows[0];
        if (d?.lat != null && haversineKm(d, { lat: r.pickup_lat, lng: r.pickup_lng }) > 1) {
          throw conflict("Trip shuru karne ke liye pickup ke paas pohnchna zaroori hai");
        }
      }
      const stamp = { arrived: "arrived_at = now()", in_trip: "started_at = now()", completed: "completed_at = now()" }[next];
      await c.query(`update rides set status = $2${stamp ? ", " + stamp : ""} where id = $1`, [id, next]);
      if (next === "completed") {
        const fare = r.accepted_fare ?? r.offered_fare;
        await c.query("insert into wallet_tx (user_id, ride_id, amount, kind, note) values ($1,$2,$3,'earning','Trip fare (cash)')", [uid, id, fare]);
        await c.query("update users set trips_count = trips_count + 1 where id in ($1,$2)", [r.driver_id, r.passenger_id]);
      }
    });
    return loadRide(pool, id, uid);
  }));

  app.post("/rides/:id/rate", wrap(async (req) => {
    const { stars } = parse(schemas.rate, req.body);
    const id = Number(req.params.id);
    const uid = req.user.id;
    await withTx(pool, async (c) => {
      const r = (await c.query("select * from rides where id = $1 for update", [id])).rows[0];
      if (!r || (r.passenger_id !== uid && r.driver_id !== uid)) throw notFound("Ride nahi mili");
      if (r.status !== "completed") throw conflict("Trip abhi complete nahi hui");
      const rider = r.passenger_id === uid;
      if ((rider ? r.driver_rating : r.passenger_rating) != null) throw conflict("Aap rate kar chuke hain");
      await c.query(`update rides set ${rider ? "driver_rating" : "passenger_rating"} = $2 where id = $1`, [id, stars]);
      await c.query("update users set rating_sum = rating_sum + $2, rating_count = rating_count + 1 where id = $1", [rider ? r.driver_id : r.passenger_id, stars]);
    });
    return { ok: true };
  }));

  /* ---- errors ---- */
  app.use((req, res) => res.status(404).json({ error: "Not found" }));
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
    if (err?.type === "entity.parse.failed") return res.status(400).json({ error: "Invalid JSON" });
    console.error(err);
    res.status(500).json({ error: "Server error" });
  });
  return app;
}
