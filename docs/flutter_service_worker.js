'use strict';

// This worker exists only to retire Flutter's former offline cache. Older
// cached bootstrap files may still register it, so it must unregister itself
// and refresh any open demo pages as soon as it activates.
self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      await self.registration.unregister();

      const cacheNames = await caches.keys();
      await Promise.all(cacheNames.map((name) => caches.delete(name)));

      const clients = await self.clients.matchAll({ type: 'window' });
      await Promise.all(
        clients.map((client) =>
          'navigate' in client ? client.navigate(client.url) : Promise.resolve(),
        ),
      );
    })(),
  );
});
