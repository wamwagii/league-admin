import "server-only";

import { Kysely, PostgresDialect } from "kysely";
import { Pool } from "pg";

import type { DB } from "./db-types";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL is not set");
}

const pool = new Pool({
  connectionString,
  max: 10,
  idleTimeoutMillis: 20_000,
  connectionTimeoutMillis: 10_000,
});

export const db = new Kysely<DB>({
  dialect: new PostgresDialect({ pool }),
});
