"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { KeyRound, ListFilter, Smartphone } from "lucide-react";
import { Button } from "@/components/ui/button";
export function Navigation() {
  const path = usePathname();
  return (
    <nav aria-label="管理菜单" className="flex flex-wrap gap-2 md:flex-col">
      {[
        { href: "/releases", title: "安卓版本", icon: Smartphone },
        { href: "/health-options", title: "健康选项", icon: ListFilter },
        { href: "/account", title: "账号安全", icon: KeyRound },
      ].map(({ href, title, icon: Icon }) => (
        <Button
          key={href}
          variant={path === href ? "secondary" : "ghost"}
          size="lg"
          className="flex-1 justify-start md:flex-none"
          nativeButton={false}
          render={
            <Link
              href={href}
              aria-current={path === href ? "page" : undefined}
            />
          }
        >
          <Icon data-icon="inline-start" />
          {title}
        </Button>
      ))}
    </nav>
  );
}
