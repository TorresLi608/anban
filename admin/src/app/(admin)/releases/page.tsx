import { requireAdmin, adminApi } from "@/lib/api";
import type { ReleaseState } from "@/lib/types";
import { ReleaseForm } from "@/components/release-form";
export const metadata = { title: "安卓版本" };
export default async function ReleasesPage() {
  await requireAdmin();
  const state = await adminApi<ReleaseState>("android-release");
  return (
    <>
      <header className="mb-9 flex flex-col gap-3">
        <p className="text-xs tracking-[.2em] text-muted-foreground">
          应用发布 / ANDROID
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">安卓版本</h1>
        <p className="text-sm leading-6 text-muted-foreground">
          维护更新信息，让使用者获取最新版本。
        </p>
      </header>
      <ReleaseForm initial={state} />
    </>
  );
}
