"use client";

import { useEffect, useState } from "react";

export function PwaRegister() {
  const [waitingWorker, setWaitingWorker] = useState<ServiceWorker | null>(null);

  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

    let refreshing = false;

    const register = async () => {
      try {
        const registration = await navigator.serviceWorker.register("/sw.js", { scope: "/" });

        if (registration.waiting) setWaitingWorker(registration.waiting);

        registration.addEventListener("updatefound", () => {
          const installing = registration.installing;
          if (!installing) return;

          installing.addEventListener("statechange", () => {
            if (installing.state === "installed" && navigator.serviceWorker.controller) {
              setWaitingWorker(registration.waiting ?? installing);
            }
          });
        });

        navigator.serviceWorker.addEventListener("controllerchange", () => {
          if (refreshing) return;
          refreshing = true;
          window.location.reload();
        });
      } catch (error) {
        console.warn("MYC service worker registration failed", error);
      }
    };

    void register();
  }, []);

  if (!waitingWorker) return null;

  return (
    <div
      role="status"
      style={{
        position: "fixed",
        left: 16,
        right: 16,
        bottom: 16,
        zIndex: 1000,
        margin: "0 auto",
        maxWidth: 520,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: 12,
        padding: "12px 14px",
        borderRadius: 14,
        background: "#12261f",
        color: "#f8fffc",
        boxShadow: "0 16px 42px rgba(18, 38, 31, .24)",
        fontSize: 13,
      }}
    >
      <span>มี MYC เวอร์ชันใหม่พร้อมใช้งาน</span>
      <button
        type="button"
        onClick={() => waitingWorker.postMessage({ type: "SKIP_WAITING" })}
        style={{
          border: 0,
          borderRadius: 10,
          padding: "9px 12px",
          fontWeight: 800,
          background: "#d9f4e9",
          color: "#0e5d47",
          cursor: "pointer",
        }}
      >
        อัปเดต
      </button>
    </div>
  );
}
