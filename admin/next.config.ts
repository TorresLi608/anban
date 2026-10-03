import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  poweredByHeader: false,
  turbopack: { root: __dirname },
  reactCompiler: true,
};

export default nextConfig;
