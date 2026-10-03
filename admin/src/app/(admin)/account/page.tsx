import { ShieldCheck } from "lucide-react";
import { requireAdmin } from "@/lib/api";
import { PasswordForm } from "@/components/password-form";
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
        <AlertTitle>修改安伴账号的登录密码</AlertTitle>
        <AlertDescription>
          保存后，该账号在管理端和手机端的登录会话都会失效，请使用新密码重新登录。资料加密密码不变，已保存的照护资料不受影响。
        </AlertDescription>
      </Alert>
      <PasswordForm />
    </div>
  );
}
