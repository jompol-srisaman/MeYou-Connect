import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    id: "/",
    name: "MeYou Connect — Founder Operations",
    short_name: "MYC",
    description: "MeYou Connect Founder Operating System",
    start_url: "/",
    scope: "/",
    display: "standalone",
    background_color: "#f5f8fc",
    theme_color: "#0F2D62",
    orientation: "portrait-primary",
    prefer_related_applications: false,
    categories: ["business", "productivity"],
    icons: [
      {
        src: "/myc-icon-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/myc-icon-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
    ],
  };
}
