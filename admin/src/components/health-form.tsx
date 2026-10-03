"use client";
import { useActionState, useState } from "react";
import { Check, Info, Save } from "lucide-react";
import { saveHealthOptions } from "@/app/actions";
import { healthFields, type HealthKey, type HealthState } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldDescription,
} from "@/components/ui/field";

const lines = (value: string) =>
  value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

export function HealthForm({ initial }: { initial: HealthState }) {
  const [result, action, pending] = useActionState(saveHealthOptions, {});
  const saved = result.data ?? initial;
  const [values, setValues] = useState(
    () =>
      Object.fromEntries(
        healthFields.map(({ key }) => [key, initial.options[key].join("\n")]),
      ) as Record<HealthKey, string>,
  );
  const dirty = healthFields.some(
    ({ key }) =>
      JSON.stringify(lines(values[key])) !== JSON.stringify(saved.options[key]),
  );
  return (
    <form action={action} className="flex flex-col gap-8">
      <input type="hidden" name="revision" value={saved.revision} />
      <Alert>
        <Info />
        <AlertTitle>保存后，用户下次登录时生效</AlertTitle>
        <AlertDescription>
          每行一个选项，每组 1–50 项，每项最多 100
          字。移除选项不会修改已经保存的健康记录。
        </AlertDescription>
      </Alert>
      <FieldGroup className="grid gap-x-10 gap-y-8 lg:grid-cols-2">
        {healthFields.map(({ key, label, description }) => {
          const items = lines(values[key]);
          const invalid =
            items.length < 1 ||
            items.length > 50 ||
            new Set(items).size !== items.length ||
            items.some((item) => [...item].length > 100);
          return (
            <Field key={key} data-invalid={invalid} data-disabled={pending}>
              <div className="flex items-center justify-between gap-3">
                <FieldLabel htmlFor={key}>{label}</FieldLabel>
                <Badge variant="secondary">{items.length} 项</Badge>
              </div>
              <FieldDescription>{description}</FieldDescription>
              <Textarea
                id={key}
                name={key}
                rows={6}
                required
                value={values[key]}
                onChange={(e) =>
                  setValues((old) => ({ ...old, [key]: e.target.value }))
                }
                disabled={pending}
                aria-invalid={invalid}
                aria-describedby={`${key}-help`}
              />
              <FieldDescription id={`${key}-help`}>
                {invalid
                  ? "请填写 1–50 个不重复选项，每项最多 100 字。"
                  : "一行一项，调整行顺序即可改变显示顺序。"}
              </FieldDescription>
            </Field>
          );
        })}
      </FieldGroup>
      {result.error && (
        <Alert variant="destructive">
          <AlertTitle>未能保存</AlertTitle>
          <AlertDescription>
            {result.error}
            <br />
            <a href="/health-options">重新载入最新配置</a>（将丢弃未保存内容）
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
        <Button type="submit" size="lg" disabled={pending || !dirty}>
          <Save data-icon="inline-start" />
          {pending ? "正在保存…" : "保存健康选项"}
        </Button>
      </div>
    </form>
  );
}
