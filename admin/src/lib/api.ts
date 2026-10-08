import "server-only";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { cache } from "react";

export const sessionCookie = "anban-admin-session";
export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message);
  }
}

export async function api<T>(
  path: string,
  options: RequestInit = {},
  token?: string,
): Promise<T> {
  const base = process.env.ANBAN_ADMIN_API_URL || "http://127.0.0.1:8024";
  let response: Response;
  try {
    response = await fetch(new URL(path, base), {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new ApiError("暂时无法连接服务，请稍后重试。", 503);
  }
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new ApiError(
      typeof body?.error === "string" ? body.error : "操作失败，请稍后重试。",
      response.status,
    );
  }
  return response.json() as Promise<T>;
}

export async function adminApi<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) throw new ApiError("登录已过期，请重新登录。", 401);
  // Go verifies the independent admin session on every read and write.
  return api<T>(`/api/v1/admin/${path}`, options, token);
}

export const currentAdmin = cache(async () => {
  try {
    return await adminApi<{ username: string }>("me");
  } catch (error) {
    if (error instanceof ApiError && [401, 403].includes(error.status))
      return null;
    throw error;
  }
});

export async function requireAdmin() {
  const admin = await currentAdmin();
  if (!admin) redirect("/login");
  return admin;
}

export function errorMessage(error: unknown) {
  return error instanceof ApiError ? error.message : "操作失败，请稍后重试。";
}
