import { ShieldCheck } from "lucide-react";
import { requireAdmin } from "@/lib/api";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";

export const metadata = { title: "账号安全" };

export default async function AccountPage() {
  const admin = await requireAdmin();
  return (
    <div className="flex max-w-2xl flex-col gap-8">
      <header className="flex flex-col gap-3">
        <p className="text-xs tracking-[.2em] text-muted-foreground">
          账号设置 / SECURITY
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">账号安全</h1>
        <p className="text-sm text-muted-foreground">
          当前账号：{admin.username}
        </p>
      </header>
      <Alert>
        <ShieldCheck />
        <AlertTitle>管理端账号由部署配置管理</AlertTitle>
        <AlertDescription>
          <p>
            修改 Go 后端环境变量 ANBAN_ADMIN_USERNAME 和 ANBAN_ADMIN_PASSWORD
            后，重新启动后端即可生效。
          </p>
          <p>
            管理端需要重新登录，App 账号密码和登录会话不受影响。
          </p>
        </AlertDescription>
      </Alert>
    </div>
  );
}
