import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { APP_CONFIG } from "@/config/app-config";

export function SupportCard() {
  const env = process.env.NODE_ENV === "production" ? "Production" : "Development";

  return (
    <Card size="sm" className="overflow-hidden shadow-none group-data-[collapsible=icon]:hidden">
      <CardHeader className="min-w-0 px-4">
        <CardTitle className="truncate text-sm">{APP_CONFIG.name}</CardTitle>
        <CardDescription className="truncate text-xs">
          v{APP_CONFIG.version} · {env}
        </CardDescription>
      </CardHeader>
    </Card>
  );
}
