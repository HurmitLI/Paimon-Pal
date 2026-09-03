import type { Metadata, Viewport } from "next";
import "./globals.css";
import { assetPath } from "./assetPath.mjs";

const title = "Paimon Pal — 住在 Mac 刘海旁的本地派蒙伙伴";
const description = "常驻 macOS 刘海的本地桌面伙伴与生产力工作台，支持桌面派蒙、本地对话、计时、音乐、待办、笔记、链接和录音。";

export const metadata: Metadata = {
  metadataBase: new URL("https://hurmitli.github.io/Paimon-Pal/"),
  title,
  description,
  applicationName: "Paimon Pal",
  keywords: ["Paimon Pal", "macOS 刘海", "桌面宠物", "本地 AI", "Apple Silicon"],
  icons: { icon: [{ url: assetPath("/favicon.png"), type: "image/png" }], shortcut: assetPath("/favicon.png"), apple: assetPath("/favicon.png") },
  openGraph: {
    type: "website",
    locale: "zh_CN",
    siteName: "Paimon Pal",
    title,
    description,
    images: [{ url: assetPath("/og.png"), width: 1200, height: 630, alt: "Paimon Pal 官网分享封面" }],
  },
  twitter: { card: "summary_large_image", title, description, images: [assetPath("/og.png")] },
};

export const viewport: Viewport = { width: "device-width", initialScale: 1, colorScheme: "dark", themeColor: "#000000" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="zh-CN"><body>{children}</body></html>;
}
