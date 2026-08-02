import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const assetBasePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Keep3 — 把最重要的三件事，留在视线里",
  description:
    "Keep3 是一块安静的原生 macOS 顶部界面，用三件重点、媒体与日历帮你在被打断后找回注意力。",
  icons: {
    icon: `${assetBasePath}/keep3-app-icon.png`,
    apple: `${assetBasePath}/keep3-app-icon.png`,
  },
  openGraph: {
    title: "Keep3 — Keep three things in sight.",
    description:
      "一块安静的原生 macOS 顶部界面，把重点、媒体与下一场日程留在视线边缘。",
    locale: "zh_CN",
    siteName: "Keep3",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
