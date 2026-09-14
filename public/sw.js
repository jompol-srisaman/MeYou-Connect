const CACHE_VERSION = "myc-pwa-v0.1.1";
const SHELL_CACHE = `${CACHE_VERSION}-shell`;
const PAGE_CACHE = `${CACHE_VERSION}-pages`;
const APP_SHELL = ["/", "/myc-icon.svg"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(SHELL_CACHE).then((cache) => cache.addAll(APP_SHELL)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => !key.startsWith(CACHE_VERSION)).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Security/data boundary: API/data responses are NEVER cached by the PWA.
  if (url.pathname.startsWith("/api/")) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then(async (response) => {
          if (response.ok && response.type === "basic") {
            const cache = await caches.open(PAGE_CACHE);
            await cache.put(request, response.clone());
          }
          return response;
        })
        .catch(async () => {
          const cachedPage = await caches.match(request);
          return cachedPage || caches.match("/");
        })
    );
    return;
  }

  if (url.pathname.startsWith("/_next/static/") || url.pathname === "/myc-icon.svg") {
    event.respondWith(
      caches.match(request).then(async (cached) => {
        if (cached) return cached;
        const response = await fetch(request);
        if (response.ok && response.type === "basic") {
          const cache = await caches.open(SHELL_CACHE);
          await cache.put(request, response.clone());
        }
        return response;
      })
    );
  }
});
