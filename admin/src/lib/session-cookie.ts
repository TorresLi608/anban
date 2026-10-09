export function shouldUseSecureCookie(requestHeaders: Pick<Headers, "get">) {
  // A Server Action's Origin reflects the browser protocol even behind a TLS proxy.
  const origin = requestHeaders.get("origin");
  if (origin) {
    try {
      return new URL(origin).protocol !== "http:";
    } catch {
      return true;
    }
  }
  // Next.js supplies this for direct requests; reverse proxies must overwrite it.
  return requestHeaders.get("x-forwarded-proto")?.split(",")[0].trim() !== "http";
}
