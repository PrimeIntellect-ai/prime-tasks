Don't include the cache-busting URL parameter in the cache key
Right now, we include the cache-busting URL parameter in the key name for the cache entries. This works fine with the logic `sw-precache` has in place for doing cache lookups, but if we excluded the cache-busting URL parameter, we would play nicely with service worker code outside of `sw-precache` that uses `caches.match()`.

### Additional contract requirements

- Add a public function `getCacheBustedUrl(url, now)` in module `lib/functions.js`, exported as part of `module.exports`. It returns a string: the original URL with a `sw-precache=<now>` query parameter appended. The parameter is appended using `&` when the URL already has query parameters, and using `?` otherwise. Other parts of the URL are left unchanged. When `now` is omitted, `Date.now()` is used.
