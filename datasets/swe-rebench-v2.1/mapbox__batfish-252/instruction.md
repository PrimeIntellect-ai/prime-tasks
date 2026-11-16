Add option to disable sitemap generation
For a lot of use cases, a sitemap isn't necessary.

### Additional contract requirements

- The new configuration option is named `sitemap` and is a boolean.
- `sitemap` defaults to `true`: sitemap generation is enabled unless the user explicitly sets `sitemap: false`.
- When `sitemap` is `false`, `generateSitemap` must not be invoked during a build.
