import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "MeYou Connect — Founder Operations",
    short_name: "MYC",
    description: "MeYou Connect Founder Operating System",
    start_url: "/",
    display: "standalone",
    background_color: "#f5f8fc",
    theme_color: "#0F2D62",
    orientation: "portrait-primary",
    categories: ["business", "productivity"],
    icons: [
      {
        src: "/myc-icon.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "any",
      },
    ],
  };
}
