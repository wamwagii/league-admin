"use client";

import type { ColumnDef } from "@tanstack/react-table";
import { Subscribe } from "@tanstack/react-table";
import { cn } from "cn";
import { format } from "date-fns";
import { MoreHorizontal } from "lucide-react";

import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { DataTableFeatures } from "@/lib/data-table-features";
import { getInitials } from "@/lib/utils";
import type { AdminUserRow } from "@/server/queries/admin-users";

const statusBadge: Record<AdminUserRow["status"], { label: string; className: string; dot: string }> = {
  active: {
    label: "Active",
    className:
      "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-900 dark:bg-emerald-950 dark:text-emerald-300",
    dot: "bg-emerald-500",
  },
  disabled: {
    label: "Disabled",
    className: "border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-900 dark:bg-rose-950 dark:text-rose-300",
    dot: "bg-rose-500",
  },
};

function StatusBadge({ status }: { status: AdminUserRow["status"] }) {
  const meta = statusBadge[status];
  return (
    <Badge variant="outline" className={cn("gap-1.5 px-2 py-1 font-medium", meta.className)}>
      <span className={cn("size-1.5 rounded-full", meta.dot)} />
      {meta.label}
    </Badge>
  );
}

export const usersColumns: ColumnDef<DataTableFeatures, AdminUserRow>[] = [
  {
    id: "select",
    header: ({ table }) => (
      <div className="flex items-center justify-center">
        <Subscribe
          source={table.atoms.rowSelection}
          selector={() =>
            table.getIsAllPageRowsSelected() ||
            (table.getIsSomePageRowsSelected() && !table.getIsAllPageRowsSelected() && "indeterminate")
          }
        >
          {(checked) => (
            <Checkbox
              aria-label="Select all"
              checked={checked}
              onCheckedChange={(value) => table.toggleAllPageRowsSelected(!!value)}
            />
          )}
        </Subscribe>
      </div>
    ),
    cell: ({ row }) => (
      <div className="flex items-center justify-center">
        <Subscribe source={row.table.atoms.rowSelection} selector={(selection) => Boolean(selection?.[row.id])}>
          {(checked) => (
            <Checkbox
              aria-label={`Select ${row.original.display_name}`}
              checked={checked}
              onCheckedChange={(value) => row.toggleSelected(!!value)}
            />
          )}
        </Subscribe>
      </div>
    ),
    enableHiding: false,
    enableSorting: false,
  },
  {
    id: "search",
    accessorFn: (row) => `${row.display_name} ${row.email}`,
    filterFn: "includesString",
    enableHiding: true,
  },
  {
    accessorKey: "display_name",
    header: "User",
    cell: ({ row }) => (
      <div className="flex items-center gap-3">
        <Avatar size="lg" className="font-medium">
          <AvatarFallback>{getInitials(row.original.display_name)}</AvatarFallback>
        </Avatar>
        <div className="min-w-0">
          <div className="text-foreground truncate text-sm font-medium">{row.original.display_name}</div>
          <div className="text-muted-foreground truncate text-sm">{row.original.email}</div>
        </div>
      </div>
    ),
  },
  {
    accessorKey: "status",
    header: "Status",
    filterFn: "equalsString",
    cell: ({ row }) => <StatusBadge status={row.original.status} />,
  },
  {
    id: "created_at",
    accessorFn: (row) => new Date(row.created_at).getTime(),
    header: "Created",
    cell: ({ row }) => (
      <div className="text-foreground text-sm">{format(new Date(row.original.created_at), "dd MMM yyyy, h:mm a")}</div>
    ),
  },
  {
    id: "actions",
    header: () => <div className="text-right">Actions</div>,
    cell: ({ row }) => (
      <div className="text-right">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              aria-label={`Open actions for ${row.original.display_name}`}
              className="text-muted-foreground hover:bg-muted/50 size-8 rounded-md"
              size="icon-sm"
              variant="ghost"
            >
              <MoreHorizontal className="size-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem disabled>View profile</DropdownMenuItem>
            <DropdownMenuItem disabled>Edit user</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem disabled variant="destructive">
              Disable user
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    ),
    enableHiding: false,
    enableSorting: false,
  },
];
