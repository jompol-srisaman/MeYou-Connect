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
  icons: {
    icon: [
      { url: "/myc-icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/myc-icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
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
