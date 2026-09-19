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
      <strong>ตอนนี้ออฟไลน์</strong>
      <span>ดูข้อมูลที่เคยเปิดได้ แต่ยังแก้ไขข้อมูลไม่ได้จนกว่าจะกลับมาออนไลน์</span>
    </div>
  );
}
