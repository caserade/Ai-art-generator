self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open('gospel-command-v2').then((cache) =>
      cache.addAll(['/', '/phone', '/manifest.webmanifest', '/gospel-kaiju.png']),
    ),
  )
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('fetch', (event) => {
  const req = event.request
  if (req.method !== 'GET') return
  event.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone()
        caches.open('gospel-command-v2').then((cache) => cache.put(req, copy))
        return res
      })
      .catch(() => caches.match(req).then((hit) => hit || caches.match('/'))),
  )
})
