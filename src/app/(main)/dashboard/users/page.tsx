import type { Metadata } from "next";

import { listAdminUsers } from "@/server/queries/admin-users";

import { Users } from "./_components/users";

export const metadata: Metadata = {
  title: "Admin Users | League Admin",
  description: "Manage admin accounts and their access.",
  alternates: {
    canonical: "/dashboard/users",
  },
};

export default async function Page() {
  const users = await listAdminUsers();
  return <Users users={users} />;
}
