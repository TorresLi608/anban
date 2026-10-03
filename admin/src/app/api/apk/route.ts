import { cookies } from "next/headers";
import { sessionCookie } from "@/lib/api";

export const runtime = "nodejs";
export const maxDuration = 600;

export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  const host =
    request.headers.get("x-forwarded-host") || request.headers.get("host");
  try {
    if (!origin || new URL(origin).host !== host)
      return Response.json({ error: "请求来源无效" }, { status: 403 });
  } catch {
    return Response.json({ error: "请求来源无效" }, { status: 403 });
  }
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token)
    return Response.json({ error: "登录已过期，请重新登录" }, { status: 401 });
  const type = request.headers.get("content-type") || "";
  if (!type.startsWith("multipart/form-data;"))
    return Response.json({ error: "请选择 APK 文件" }, { status: 400 });
  const length = Number(request.headers.get("content-length"));
  if (length > 301 * 1024 * 1024)
    return Response.json({ error: "安装包不能超过 300 MB" }, { status: 413 });
  try {
    // Stream the upload to Go; never buffer the APK in the Next.js process.
    const options: RequestInit & { duplex: "half" } = {
      method: "POST",
      body: request.body,
      duplex: "half",
      cache: "no-store",
      headers: { "Content-Type": type, Authorization: `Bearer ${token}` },
      signal: AbortSignal.any([request.signal, AbortSignal.timeout(600_000)]),
    };
    const upstream = await fetch(
      new URL(
        "/api/v1/admin/apks",
        process.env.ANBAN_ADMIN_API_URL || "http://127.0.0.1:8024",
      ),
      options,
    );
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  } catch {
    return Response.json(
      { error: "上传失败，请检查网络后重试" },
      { status: 503 },
    );
  }
}
