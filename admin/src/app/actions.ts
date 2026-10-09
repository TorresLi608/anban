"use server";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { adminApi, api, errorMessage, sessionCookie } from "@/lib/api";
import { shouldUseSecureCookie } from "@/lib/session-cookie";
import {
  healthFields,
  type ActionResult,
  type HealthState,
  type ReleaseState,
} from "@/lib/types";

export async function login(
  _: ActionResult,
  form: FormData,
): Promise<ActionResult> {
  const username = String(form.get("username") || "").trim();
  const password = String(form.get("password") || "");
  if (
    !/^[a-zA-Z0-9_]{3,32}$/.test(username) ||
    [...password].length < 6 ||
    Buffer.byteLength(password) > 72
  )
    return { error: "请输入有效账号和密码。" };
  try {
    const result = await api<{ token: string }>("/api/v1/admin/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
    });
    if (!/^[a-f0-9]{64}$/.test(result.token))
      return { error: "登录响应无效，请稍后重试。" };
    (await cookies()).set(sessionCookie, result.token, {
      httpOnly: true,
      secure: shouldUseSecureCookie(await headers()),
      sameSite: "strict",
      path: "/",
      maxAge: 8 * 60 * 60,
    });
  } catch (error) {
    return { error: errorMessage(error) };
  }
  redirect("/releases");
}

export async function logout() {
  const jar = await cookies();
  const token = jar.get(sessionCookie)?.value;
  if (token) {
    try {
      await api("/api/v1/admin/logout", { method: "POST" }, token);
    } catch {
      /* Clear this browser's session even when the backend is unreachable. */
    }
  }
  jar.delete(sessionCookie);
  redirect("/login");
}

export async function saveRelease(
  previous: ActionResult<ReleaseState>,
  form: FormData,
): Promise<ActionResult<ReleaseState>> {
  const versionName = String(form.get("versionName") || "").trim();
  const downloadUrl = String(form.get("downloadUrl") || "").trim();
  const releaseNotes = String(form.get("releaseNotes") || "")
    .replace(/\r\n?/g, "\n")
    .trim();
  const rawCode = String(form.get("versionCode") || "");
  const release =
    rawCode || versionName || downloadUrl || releaseNotes
      ? { versionCode: Number(rawCode), versionName, downloadUrl, releaseNotes }
      : null;
  const rawRevision = String(form.get("revision") ?? "");
  if (!/^\d+$/.test(rawRevision))
    return { data: previous.data, error: "请刷新页面后重新编辑。" };
  try {
    const data = await adminApi<ReleaseState>("android-release", {
      method: "PUT",
      body: JSON.stringify({
        revision: Number(rawRevision),
        enabled: form.get("enabled") === "true",
        release,
      }),
    });
    return {
      data,
      success: data.enabled
        ? "已保存并发布，安卓端下次检查时生效。"
        : "已保存，更新提示已暂停。",
    };
  } catch (error) {
    return { data: previous.data, error: errorMessage(error) };
  }
}

export async function saveHealthOptions(
  previous: ActionResult<HealthState>,
  form: FormData,
): Promise<ActionResult<HealthState>> {
  const options = Object.fromEntries(
    healthFields.map(({ key }) => [
      key,
      String(form.get(key) || "")
        .split(/\r?\n/)
        .map((value) => value.trim())
        .filter(Boolean),
    ]),
  );
  try {
    const data = await adminApi<HealthState>("health-options", {
      method: "PUT",
      body: JSON.stringify({
        revision: String(form.get("revision") || ""),
        options,
      }),
    });
    return { data, success: "健康选项已保存，用户下次登录时生效。" };
  } catch (error) {
    return { data: previous.data, error: errorMessage(error) };
  }
}
