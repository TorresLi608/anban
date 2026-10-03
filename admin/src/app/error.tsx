"use client";
import { Button } from "@/components/ui/button";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <div className="mx-auto flex w-full max-w-lg flex-col gap-5 p-8 py-20">
      <Alert variant="destructive">
        <AlertTitle>暂时无法加载管理页面</AlertTitle>
        <AlertDescription>
          请确认服务可用后重试。尚未提交的修改不会自动保存。
        </AlertDescription>
      </Alert>
      <Button onClick={reset}>重新加载</Button>
      <a
        href="/login"
        className="text-center text-sm underline underline-offset-4"
      >
        返回登录页
      </a>
    </div>
  );
}
