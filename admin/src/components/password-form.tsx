"use client";

import { useActionState } from "react";
import { KeyRound } from "lucide-react";
import { changePassword } from "@/app/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";

export function PasswordForm() {
  const [state, action, pending] = useActionState(changePassword, {});
  return (
    <form action={action} className="max-w-lg">
      <FieldGroup>
        <Field data-disabled={pending}>
          <FieldLabel htmlFor="currentPassword">当前密码</FieldLabel>
          <Input
            id="currentPassword"
            name="currentPassword"
            type="password"
            autoComplete="current-password"
            required
            disabled={pending}
          />
        </Field>
        <Field data-disabled={pending}>
          <FieldLabel htmlFor="newPassword">新密码</FieldLabel>
          <Input
            id="newPassword"
            name="newPassword"
            type="password"
            autoComplete="new-password"
            required
            minLength={6}
            disabled={pending}
            aria-describedby="password-help"
          />
          <FieldDescription id="password-help">
            至少 6 个字符，最多 72 个 UTF-8 字节。
          </FieldDescription>
        </Field>
        <Field data-disabled={pending}>
          <FieldLabel htmlFor="confirmation">确认新密码</FieldLabel>
          <Input
            id="confirmation"
            name="confirmation"
            type="password"
            autoComplete="new-password"
            required
            minLength={6}
            disabled={pending}
          />
        </Field>
        {state.error && <FieldError>{state.error}</FieldError>}
        <Button type="submit" size="lg" disabled={pending}>
          <KeyRound data-icon="inline-start" />
          {pending ? "正在修改…" : "修改密码并重新登录"}
        </Button>
      </FieldGroup>
    </form>
  );
}
