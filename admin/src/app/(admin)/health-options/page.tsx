import { requireAdmin, adminApi } from "@/lib/api";
import type { HealthState } from "@/lib/types";
import { HealthForm } from "@/components/health-form";
export const metadata = { title: "健康选项" };
export default async function HealthOptionsPage() {
  await requireAdmin();
  const state = await adminApi<HealthState>("health-options");
  return (
    <>
      <header className="mb-9 flex flex-col gap-3">
        <p className="text-xs tracking-[.2em] text-muted-foreground">
          记录设置 / OPTIONS
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">健康选项</h1>
        <p className="text-sm leading-6 text-muted-foreground">
          管理健康记录中的可选内容，按行填写，按顺序显示。
        </p>
      </header>
      <HealthForm initial={state} />
    </>
  );
}
