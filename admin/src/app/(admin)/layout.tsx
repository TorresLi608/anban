import { Sprout, LogOut, ShieldCheck } from "lucide-react";
import { requireAdmin } from "@/lib/api";
import { logout } from "@/app/actions";
import { Navigation } from "@/components/navigation";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const admin = await requireAdmin();
  return (
    <div className="min-h-svh md:grid md:grid-cols-[224px_minmax(0,1fr)]">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:bg-background focus:p-4"
      >
        跳至主要内容
      </a>
      <aside className="flex flex-col gap-6 border-b border-border bg-sidebar px-5 py-6 md:sticky md:top-0 md:h-svh md:border-r md:border-b-0 md:py-8">
        <div className="flex items-center gap-3 px-2 text-primary">
          <Sprout className="size-7" />
          <div>
            <p className="text-xl font-semibold tracking-wide">安伴</p>
            <p className="mt-1 text-xs text-muted-foreground">应用管理</p>
          </div>
        </div>
        <div className="md:mt-8">
          <Navigation />
        </div>
        <div className="flex items-center justify-between gap-3 md:mt-auto md:flex-col md:items-stretch">
          <div className="hidden md:block">
            <Separator />
          </div>
          <div className="flex min-w-0 items-center gap-2 px-2 text-sm">
            <ShieldCheck className="size-4 shrink-0 text-primary" />
            <span className="truncate">{admin.username}</span>
          </div>
          <form action={logout}>
            <Button
              variant="ghost"
              type="submit"
              className="justify-start md:w-full"
            >
              <LogOut data-icon="inline-start" />
              退出登录
            </Button>
          </form>
        </div>
      </aside>
      <main id="main" className="min-w-0 px-6 py-8 sm:px-10 md:py-12 xl:px-16">
        <div className="mx-auto max-w-6xl">{children}</div>
      </main>
    </div>
  );
}
