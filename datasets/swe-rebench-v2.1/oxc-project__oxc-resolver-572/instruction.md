Support non-standard "use exports field for directory resolution" behavior
Vite currently uses `exports` field when resolving directory specifiers.
For example, when `import './dir'` is written, Vite uses `exports` field of `./dir/package.json` if exists.

Node.js does not use `exports` field in this case (https://github.com/nodejs/node/issues/58827). While Vite probably should not have supported this, there are some code that relies on this behavior ([nuxt](https://github.com/nuxt/nuxt/blob/a7d21ece19e69703aac5fbb1f7bf53f0dfc5751f/test/setup-env.ts#L3), [Vitest](https://github.com/vitest-dev/vitest/blob/176133ed0cc5c8d04d0faa2e58d4a4f9cf3b78a6/test/core/test/resolve-web.test.ts#L4-L5)). We prefer to not break these if possible.

To achieve that, it would be nice if oxc-resolver adds an option that opt-in to this behavior.

related: https://github.com/vitejs/vite/pull/20252

### Additional contract requirements

Callers can opt in to this behavior through the `ResolveOptions` option named `allow_package_exports_in_directory_resolve`. It is disabled by default; when enabled, resolving a directory specifier consults that directory's package `exports` field.
