import {
  Calendar,
  ClipboardList,
  LayoutDashboard,
  Lock,
  type LucideIcon,
  RefreshCw,
  Settings,
  Trophy,
  UserRound,
  Users,
  UsersRound,
} from "lucide-react";

export type NavBadge = "new" | "updated" | "soon";

export interface NavSubItem {
  id: string;
  title: string;
  url: string;
  icon?: LucideIcon;
  badge?: NavBadge;
  disabled?: boolean;
  newTab?: boolean;
}

interface NavItemBase {
  id: string;
  title: string;
  icon?: LucideIcon;
  badge?: NavBadge;
  disabled?: boolean;
  newTab?: boolean;
}

export interface NavMainLinkItem extends NavItemBase {
  url: string;
  subItems?: never;
}

export interface NavMainParentItem extends NavItemBase {
  subItems: NavSubItem[];
}

export type NavMainItem = NavMainLinkItem | NavMainParentItem;

export interface NavGroup {
  id: number;
  label?: string;
  items: NavMainItem[];
}

export const sidebarItems: NavGroup[] = [
  {
    id: 1,
    label: "Overview",
    items: [
      {
        id: "dashboard",
        title: "Dashboard",
        url: "/dashboard/default",
        icon: LayoutDashboard,
      },
    ],
  },
  {
    id: 2,
    label: "Competitions",
    items: [
      {
        id: "competition-groups",
        title: "Competition Groups",
        url: "/dashboard/competition-groups",
        icon: Trophy,
        disabled: true,
      },
      {
        id: "teams",
        title: "Teams",
        url: "/dashboard/teams",
        icon: UsersRound,
        disabled: true,
      },
      {
        id: "registrations",
        title: "Registrations",
        url: "/dashboard/registrations",
        icon: ClipboardList,
        disabled: true,
      },
    ],
  },
  {
    id: 3,
    label: "Fixtures & Results",
    items: [
      {
        id: "fixtures",
        title: "Fixtures",
        url: "/dashboard/fixtures",
        icon: Calendar,
        disabled: true,
      },
      {
        id: "results",
        title: "Results",
        url: "/dashboard/results",
        icon: Trophy,
        disabled: true,
      },
      {
        id: "standings",
        title: "Standings",
        url: "/dashboard/standings",
        icon: Trophy,
        disabled: true,
      },
      {
        id: "movements",
        title: "Movements",
        url: "/dashboard/movements",
        icon: RefreshCw,
        disabled: true,
      },
    ],
  },
  {
    id: 4,
    label: "Administration",
    items: [
      {
        id: "users",
        title: "Admin Users",
        url: "/dashboard/users",
        icon: Users,
      },
      {
        id: "roles",
        title: "Roles",
        url: "/dashboard/roles",
        icon: Lock,
      },
      {
        id: "profile",
        title: "Profile",
        url: "/dashboard/profile",
        icon: UserRound,
      },
      {
        id: "settings",
        title: "Settings",
        url: "/dashboard/settings",
        icon: Settings,
        disabled: true,
      },
    ],
  },
];
