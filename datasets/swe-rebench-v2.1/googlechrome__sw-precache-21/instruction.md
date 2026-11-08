sw-precache and implicit index.html rewrites
Many servers are configured to handle a request for a bare directory URL as being equivalent to the request for `index.html` within that directory.

It's possible, but not intuitive, to handle this using the [`dynamicUrlToDependencies`](https://github.com/GoogleChrome/sw-precache/blob/master/demo/gulpfile.js#L39) parameter. This approach also forces you to list entries for every directory that has an implicit `index.html` rewrite.

At the very least, the docs should clarify this behavior. Better, `sw-precache` should add a new option to configure what bare directories get rewritten to (e.g. `index.html, `index.php`, `index`) and should automatically handle serving the appropriate file without the need for [`dynamicUrlToDependencies`] mappings.

### Additional contract requirements

- The new option is named `directoryIndex`. It is a `String` and defaults to `'index.html'`.
- The generated service worker uses the configured `directoryIndex` value to rewrite bare directory URLs (URLs ending in `'/'` or with no explicit pathname) to the corresponding index file, and automatically serves that file from the precache without requiring a `dynamicUrlToDependencies` mapping for the directory.
