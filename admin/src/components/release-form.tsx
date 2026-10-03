"use client";
import { useActionState, useEffect, useRef, useState } from "react";
import { Check, ExternalLink, Info, Save } from "lucide-react";
import { saveRelease } from "@/app/actions";
import type { ReleaseState } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
  Field,
  FieldContent,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";

export function ReleaseForm({ initial }: { initial: ReleaseState }) {
  const [result, action, pending] = useActionState(saveRelease, {});
  const saved = result.data ?? initial;
  const [enabled, setEnabled] = useState(initial.enabled);
  const [upload, setUpload] = useState({
    busy: false,
    progress: 0,
    error: "",
    name: "",
  });
  const uploadRequest = useRef<XMLHttpRequest | null>(null);
  useEffect(() => () => uploadRequest.current?.abort(), []);
  const [values, setValues] = useState({
    versionCode: initial.release?.versionCode.toString() ?? "",
    versionName: initial.release?.versionName ?? "",
    downloadUrl: initial.release?.downloadUrl ?? "",
    releaseNotes: initial.release?.releaseNotes ?? "",
  });
  const update = (key: keyof typeof values, value: string) =>
    setValues((old) => ({ ...old, [key]: value }));
  function uploadAPK(file: File) {
    if (
      !file.name.toLowerCase().endsWith(".apk") ||
      file.size === 0 ||
      file.size > 300 * 1024 * 1024
    ) {
      setUpload({
        busy: false,
        progress: 0,
        name: "",
        error: "请选择不超过 300 MB 的 .apk 文件。",
      });
      return;
    }
    setUpload({ busy: true, progress: 0, error: "", name: file.name });
    const body = new FormData();
    body.append("file", file);
    const xhr = new XMLHttpRequest();
    uploadRequest.current = xhr;
    xhr.open("POST", "/api/apk");
    xhr.timeout = 600_000;
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable)
        setUpload((old) => ({
          ...old,
          progress: Math.round((event.loaded / event.total) * 100),
        }));
    };
    const failed = (error: string) =>
      setUpload((old) => ({ ...old, busy: false, error }));
    xhr.onerror = xhr.ontimeout = () => failed("上传失败，请检查网络后重试。");
    xhr.onabort = () => failed("上传已取消。");
    xhr.onload = () => {
      try {
        const result = JSON.parse(xhr.responseText);
        if (xhr.status !== 200) {
          failed(result.error || "上传失败，请稍后重试。");
          return;
        }
        const url = new URL(result.downloadUrl);
        if (url.protocol !== "https:" || url.username || url.password)
          throw new Error("Invalid upload URL");
        update("downloadUrl", url.href);
        setUpload({ busy: false, progress: 100, error: "", name: file.name });
      } catch {
        failed("上传结果无效，请稍后重试。");
      }
    };
    xhr.send(body);
  }
  const hasContent = Object.values(values).some((value) => value.trim());
  const dirty =
    enabled !== saved.enabled ||
    Object.entries(values).some(
      ([key, value]) =>
        value.replace(/\r\n?/g, "\n").trim() !==
        String(
          saved.release?.[key as keyof NonNullable<ReleaseState["release"]>] ??
            "",
        ).replace(/\r\n?/g, "\n"),
    );
  return (
    <div className="grid items-start gap-10 xl:grid-cols-[minmax(0,1fr)_280px] xl:gap-14">
      <form action={action} className="flex min-w-0 flex-col gap-7">
        <input type="hidden" name="revision" value={saved.revision} />
        <input type="hidden" name="enabled" value={String(enabled)} />
        <FieldGroup>
          <Field orientation="horizontal" data-disabled={pending}>
            <FieldContent>
              <FieldLabel htmlFor="enabled">向用户提示更新</FieldLabel>
              <FieldDescription>
                开启并保存后，旧版本用户会收到更新提示。
              </FieldDescription>
            </FieldContent>
            <Switch
              id="enabled"
              checked={enabled}
              onCheckedChange={setEnabled}
              disabled={pending}
            />
          </Field>
          <Separator />
          <FieldGroup className="grid sm:grid-cols-2">
            <Field>
              <FieldLabel htmlFor="versionName">版本名称</FieldLabel>
              <Input
                id="versionName"
                name="versionName"
                placeholder="例如 1.0.1"
                required={enabled || hasContent}
                maxLength={64}
                value={values.versionName}
                onChange={(e) => update("versionName", e.target.value)}
                disabled={pending}
              />
              <FieldDescription>显示给使用者的版本号。</FieldDescription>
            </Field>
            <Field>
              <FieldLabel htmlFor="versionCode">版本编号</FieldLabel>
              <Input
                id="versionCode"
                name="versionCode"
                type="number"
                min={Math.max(1, saved.release?.versionCode ?? 1)}
                max={2100000000}
                step={1}
                placeholder="例如 2"
                required={enabled || hasContent}
                value={values.versionCode}
                onChange={(e) => update("versionCode", e.target.value)}
                disabled={pending}
              />
              <FieldDescription>与 APK 一致；新版必须递增。</FieldDescription>
            </Field>
          </FieldGroup>
          <Field>
            <FieldLabel htmlFor="apk">上传 APK 安装包</FieldLabel>
            <Input
              id="apk"
              type="file"
              accept=".apk,application/vnd.android.package-archive"
              disabled={pending || upload.busy}
              aria-invalid={Boolean(upload.error)}
              aria-describedby="apk-status"
              onChange={(event) => {
                const file = event.target.files?.[0];
                event.target.value = "";
                if (file) uploadAPK(file);
              }}
            />
            <FieldDescription id="apk-status" role="status">
              {upload.error ||
                (upload.busy
                  ? upload.progress < 100
                    ? `正在上传 ${upload.name} · ${upload.progress}%`
                    : "文件已发送，正在保存…"
                  : upload.name
                    ? `${upload.name} 已上传，下载地址已生成。请保存发布。`
                    : "选择 anban.apk，上传后自动生成下载地址。最大 300 MB。")}
            </FieldDescription>
            {upload.busy && (
              <Button
                type="button"
                variant="ghost"
                onClick={() => uploadRequest.current?.abort()}
              >
                取消上传
              </Button>
            )}
          </Field>
          <Field>
            <FieldLabel htmlFor="downloadUrl">下载地址</FieldLabel>
            <Input
              id="downloadUrl"
              name="downloadUrl"
              type="url"
              placeholder="上传安装包后自动生成"
              required={enabled || hasContent}
              value={values.downloadUrl}
              readOnly
              disabled={pending}
            />
            <FieldDescription>
              自动生成的公开下载链接，使用者无需登录即可下载。
            </FieldDescription>
          </Field>
          <Field>
            <FieldLabel htmlFor="releaseNotes">
              更新说明 <span className="text-muted-foreground">（选填）</span>
            </FieldLabel>
            <Textarea
              id="releaseNotes"
              name="releaseNotes"
              rows={6}
              placeholder="告诉使用者，这次更新有哪些变化。"
              value={values.releaseNotes}
              onChange={(e) => update("releaseNotes", e.target.value)}
              disabled={pending}
            />
            <FieldDescription>
              最多 4000 字节，约 1300 个汉字。
            </FieldDescription>
          </Field>
        </FieldGroup>
        {result.error && (
          <Alert variant="destructive">
            <AlertTitle>未能保存</AlertTitle>
            <AlertDescription>
              {result.error}
              <br />
              <a href="/releases">重新载入最新配置</a>（将丢弃未保存内容）
            </AlertDescription>
          </Alert>
        )}
        <Separator />
        <div className="flex flex-wrap items-center justify-between gap-4">
          <p
            role="status"
            className="flex items-center gap-2 text-sm text-muted-foreground"
          >
            {dirty ? (
              "有未保存的修改"
            ) : result.success ? (
              <>
                <Check className="size-4 text-primary" />
                {result.success}
              </>
            ) : (
              "当前配置已同步"
            )}
          </p>
          <Button
            type="submit"
            size="lg"
            disabled={pending || upload.busy || !dirty}
          >
            <Save data-icon="inline-start" />
            {pending ? "正在保存…" : enabled ? "保存并发布" : "保存配置"}
          </Button>
        </div>
      </form>
      <aside className="flex flex-col gap-6 border-t border-border pt-7 xl:border-t-0 xl:border-l xl:pt-0 xl:pl-8">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-sm font-medium">当前发布</h2>
          <Badge variant={saved.enabled ? "default" : "secondary"}>
            {saved.enabled ? "已启用" : "未启用"}
          </Badge>
        </div>
        <div>
          <p className="break-all text-4xl font-medium tracking-tight">
            {saved.release?.versionName ?? "尚未发布"}
          </p>
          {saved.release && (
            <p className="mt-3 text-sm text-muted-foreground">
              版本编号 {saved.release.versionCode}
            </p>
          )}
        </div>
        <dl className="flex flex-col gap-2 text-sm">
          <dt className="text-muted-foreground">最近保存</dt>
          <dd>
            {new Date(saved.updatedAt).toLocaleString("zh-CN", {
              timeZone: "Asia/Shanghai",
              hour12: false,
            })}
          </dd>
        </dl>
        {saved.release && (
          <Button
            variant="outline"
            nativeButton={false}
            render={
              <a
                href={saved.release.downloadUrl}
                target="_blank"
                rel="noopener noreferrer"
              />
            }
          >
            <ExternalLink data-icon="inline-start" />
            打开下载地址
          </Button>
        )}
        <Alert>
          <Info />
          <AlertTitle>发布前确认</AlertTitle>
          <AlertDescription>
            上传成功后点击“保存并发布”。新旧安装包需使用相同包名和签名。
          </AlertDescription>
        </Alert>
      </aside>
    </div>
  );
}
