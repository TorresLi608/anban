import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: { default: "安伴管理", template: "%s · 安伴管理" },
  description: "安伴应用版本与健康选项管理",
  robots: { index: false, follow: false },
};
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
