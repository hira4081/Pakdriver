import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import pg from "pg";

pg.types.setTypeParser(20, (v) => Number(v)); // bigint -> number

export function createPool(connectionString = process.env.DATABASE_URL, opts = {}) {
  if (!connectionString) throw new Error("DATABASE_URL is required");
  const ssl =
    process.env.PGSSL === "1" || /sslmode=require/.test(connectionString)
      ? { rejectUnauthorized: false }
      : undefined;
  return new pg.Pool({ connectionString, ssl, ...opts });
}

export async function migrate(pool) {
  const sql = readFileSync(fileURLToPath(new URL("./schema.sql", import.meta.url)), "utf8");
  await pool.query(sql);
}

/** Run fn inside a transaction on a single client. */
export async function withTx(pool, fn) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const out = await fn(client);
    await client.query("commit");
    return out;
  } catch (e) {
    await client.query("rollback").catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}
