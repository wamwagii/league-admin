import { sql } from "kysely";

import { db } from "../src/server/db";

async function main() {
  const nowResult = await sql<{ now: Date }>`SELECT now() as now`.execute(db);
  console.log("Connected. Server time:", nowResult.rows[0].now);

  const tableList = await sql<{ table_name: string }>`
    SELECT table_name
      FROM information_schema.tables
     WHERE table_schema = 'public'
     ORDER BY table_name
  `.execute(db);

  console.log(`\nTables (${tableList.rows.length}):`);
  for (const row of tableList.rows) {
    console.log(" -", row.table_name);
  }

  const userCount = await sql<{ count: number }>`
    SELECT COUNT(*)::int AS count FROM admin_users
  `.execute(db);
  console.log(`\nadmin_users rows: ${userCount.rows[0].count}`);

  await db.destroy();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
