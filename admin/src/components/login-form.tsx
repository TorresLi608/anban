"use client";
import { useActionState } from "react";
import { ArrowRight } from "lucide-react";
import { login } from "@/app/actions";
import { Button } from "@/components/ui/button";
import {
  Field,
  FieldLabel,
  FieldGroup,
  FieldError,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
export function LoginForm() {
  const [state, action, pending] = useActionState(login, {});
  return (
    <form action={action} className="w-full">
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="username">账号</FieldLabel>
          <Input
            id="username"
            name="username"
            autoComplete="username"
            placeholder="管理端账号"
            required
            minLength={3}
            maxLength={32}
            autoCapitalize="none"
            spellCheck={false}
            disabled={pending}
          />
        </Field>
        <Field>
          <FieldLabel htmlFor="password">密码</FieldLabel>
          <Input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            placeholder="输入管理端密码"
            required
            minLength={6}
            disabled={pending}
          />
        </Field>
        {state.error && <FieldError>{state.error}</FieldError>}
        <Button type="submit" size="lg" disabled={pending} className="w-full">
          {pending ? "正在登录…" : "登录管理端"}
          <ArrowRight data-icon="inline-end" />
        </Button>
      </FieldGroup>
    </form>
  );
}
