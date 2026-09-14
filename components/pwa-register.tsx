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
    <div className="pwa-update-banner" role="status" aria-live="polite">
      <div>
        <strong>มี MYC เวอร์ชันใหม่</strong>
        <span>อัปเดตเมื่อพร้อม ระบบจะรีโหลดหนึ่งครั้ง</span>
      </div>
      <button type="button" onClick={() => waitingWorker.postMessage({ type: "SKIP_WAITING" })}>
        อัปเดต
      </button>
    </div>
  );
}
