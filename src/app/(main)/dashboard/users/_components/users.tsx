"use client";

import * as React from "react";

import { type ColumnFiltersState, type PaginationState, type SortingState, useTable } from "@tanstack/react-table";
import { Plus, Search } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { dataTableFeatures } from "@/lib/data-table-features";
import type { AdminUserRow } from "@/server/queries/admin-users";

import { usersColumns } from "./users-columns";
import { UsersTable } from "./users-table";

const statusOptions = ["All", "active", "disabled"] as const;

export function Users({ users }: { users: AdminUserRow[] }) {
  const [rowSelection, setRowSelection] = React.useState({});
  const [sorting, setSorting] = React.useState<SortingState>([{ id: "created_at", desc: true }]);
  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>([]);
  const [pagination, setPagination] = React.useState<PaginationState>({
    pageIndex: 0,
    pageSize: 10,
  });

  const table = useTable({
    features: dataTableFeatures,
    data: users,
    columns: usersColumns,
    state: {
      rowSelection,
      sorting,
      columnFilters,
      pagination,
    },
    getRowId: (row) => row.id,
    autoResetPageIndex: false,
    enableRowSelection: true,
    onRowSelectionChange: setRowSelection,
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    onPaginationChange: setPagination,
  });

  const searchQuery = (table.getColumn("search")?.getFilterValue() as string | undefined) ?? "";
  const statusFilter = (table.getColumn("status")?.getFilterValue() as string | undefined) ?? "All";
  const selectedCount = table.getFilteredSelectedRowModel().rows.length;

  return (
    <Card>
      <CardHeader className="border-b has-data-[slot=card-action]:grid-cols-1 md:has-data-[slot=card-action]:grid-cols-[1fr_auto]">
        <CardTitle className="text-xl leading-none">Admin Users</CardTitle>
        <CardDescription className="max-w-sm leading-snug">Manage admin accounts and their access.</CardDescription>
        <CardAction className="col-start-1 row-start-auto flex w-full flex-wrap justify-start gap-2 justify-self-stretch md:col-start-2 md:row-span-2 md:row-start-1 md:w-auto md:flex-nowrap md:justify-end md:justify-self-end">
          <InputGroup className="h-7 w-full md:w-64">
            <InputGroupAddon align="inline-start">
              <Search className="size-3.5" />
            </InputGroupAddon>
            <InputGroupInput
              className="h-7"
              placeholder="Search by name or email..."
              value={searchQuery}
              onChange={(event) => {
                table.getColumn("search")?.setFilterValue(event.target.value || undefined);
                table.setPageIndex(0);
              }}
            />
          </InputGroup>
          <Button size="sm" disabled>
            <Plus /> Add User
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-4 px-0">
        <div className="flex flex-wrap items-center justify-between gap-3 px-4">
          <Select
            value={statusFilter}
            onValueChange={(value) => {
              table.getColumn("status")?.setFilterValue(value === "All" ? undefined : value);
              table.setPageIndex(0);
            }}
          >
            <SelectTrigger size="sm">
              <span className="text-muted-foreground">Status:</span>
              <SelectValue />
            </SelectTrigger>
            <SelectContent position="popper" align="start">
              <SelectGroup>
                {statusOptions.map((option) => (
                  <SelectItem key={option} value={option}>
                    {option === "All" ? "All" : option.charAt(0).toUpperCase() + option.slice(1)}
                  </SelectItem>
                ))}
              </SelectGroup>
            </SelectContent>
          </Select>

          <div className="text-muted-foreground text-sm tabular-nums">{selectedCount} selected</div>
        </div>

        <UsersTable table={table} />
      </CardContent>
    </Card>
  );
}
