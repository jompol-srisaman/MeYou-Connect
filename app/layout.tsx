import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { PwaRegister } from "@/components/pwa-register";
import "./globals.css";
import "./pwa.css";
import "./live-read.css";

export const metadata: Metadata = {
  title: "MYC Founder Operations",
  description: "MeYou Connect Founder Operating System",
  applicationName: "MYC",
  manifest: "/manifest.webmanifest",
  icons: { icon: "/myc-icon.svg", apple: "/myc-icon.svg" },
  appleWebApp: { capable: true, title: "MYC", statusBarStyle: "black-translucent" },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#0F2D62",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return <html lang="th"><body>{children}<PwaRegister /></body></html>;
}
