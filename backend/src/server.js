import { createApp, googleVerifier } from "./app.js";
import { createPool, migrate } from "./db.js";

const need = (k) => {
  const v = process.env[k];
  if (!v) throw new Error(`${k} environment variable is required`);
  return v;
};

const pool = createPool();
await migrate(pool);

const clientIds = need("GOOGLE_CLIENT_IDS").split(",").map((s) => s.trim()).filter(Boolean);
const app = createApp({
  pool,
  jwtSecret: need("JWT_SECRET"),
  verifyGoogle: googleVerifier(clientIds),
  corsOrigin: process.env.CORS_ORIGIN || "*",
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => console.log(`PakDrive API listening on :${port}`));
