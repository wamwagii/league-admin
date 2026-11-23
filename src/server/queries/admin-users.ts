import "server-only";

import { db } from "@/server/db";
import type { AdminUsers, UserStatus } from "@/server/db-types";

export type AdminUserRow = Pick<AdminUsers, "id" | "display_name" | "email" | "status" | "created_at">;
export type AdminUserStatus = UserStatus;

export async function listAdminUsers(): Promise<AdminUserRow[]> {
  return db
    .selectFrom("admin_users")
    .select(["id", "display_name", "email", "status", "created_at"])
    .orderBy("created_at", "desc")
    .execute();
}
