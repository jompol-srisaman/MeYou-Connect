import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "MeYou Connect — Founder Operations",
    short_name: "MYC",
    description: "MeYou Connect Founder Operating System",
    start_url: "/",
    display: "standalone",
    background_color: "#f4f7f6",
    theme_color: "#12261f",
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
