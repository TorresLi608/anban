import { Sprout, ShieldCheck } from "lucide-react";
import { redirect } from "next/navigation";
import { currentAdmin } from "@/lib/api";
import { LoginForm } from "@/components/login-form";
import { Separator } from "@/components/ui/separator";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
export const metadata = { title: "登录" };
export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ passwordChanged?: string }>;
}) {
  if (await currentAdmin()) redirect("/releases");
  const { passwordChanged } = await searchParams;
  return (
    <main className="flex min-h-svh flex-col p-6 sm:p-10">
      <div className="flex items-center gap-3 text-primary">
        <Sprout className="size-7" />
        <span className="text-xl font-semibold tracking-wide">
          安伴{" "}
          <span className="ml-2 text-sm font-normal text-muted-foreground">
            管理端
          </span>
        </span>
      </div>
      <div className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-8 py-16">
        <div className="flex flex-col gap-3">
          <p className="text-xs tracking-[.2em] text-muted-foreground">
            ANBAN / ADMIN
          </p>
          <h1 className="text-3xl font-semibold tracking-tight">登录管理端</h1>
          <p className="text-sm leading-6 text-muted-foreground">
            管理应用版本与健康记录选项。
          </p>
        </div>
        {passwordChanged === "1" && (
          <Alert>
            <AlertTitle>密码已修改</AlertTitle>
            <AlertDescription>
              旧会话已退出，请使用新密码登录。
            </AlertDescription>
          </Alert>
        )}
        <LoginForm />
        <Separator />
        <p className="flex items-start gap-2 text-xs leading-6 text-muted-foreground">
          <ShieldCheck className="mt-1 size-4 shrink-0" />
          仅向已授权的管理员开放。请使用安伴账号密码登录，无需资料加密密码。
        </p>
      </div>
      <p className="text-center text-xs text-muted-foreground">
        安伴 · 居家照护
      </p>
    </main>
  );
}
