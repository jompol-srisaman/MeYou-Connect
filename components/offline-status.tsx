"use client";

import { useEffect, useState } from "react";

export function OfflineStatus() {
  const [online, setOnline] = useState(true);

  useEffect(() => {
    const sync = () => setOnline(navigator.onLine);
    sync();
    window.addEventListener("online", sync);
    window.addEventListener("offline", sync);
    return () => {
      window.removeEventListener("online", sync);
      window.removeEventListener("offline", sync);
    };
  }, []);

  if (online) return null;

  return (
    <div className="offline-banner" role="status" aria-live="polite">
      <strong>ออฟไลน์</strong>
      <span>อ่านหน้าที่เคยเปิดได้เท่านั้น · การเปลี่ยนข้อมูลถูกปิดและต้องตรวจซ้ำเมื่อออนไลน์</span>
    </div>
  );
}
