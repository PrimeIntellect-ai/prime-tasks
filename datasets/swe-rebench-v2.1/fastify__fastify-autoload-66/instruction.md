Type definition files should not attempt to be loaded
## 🐛 Bug Report

When using `includeTypeScript: true`, fastify-autload will attempt to load type definition files (`.d.ts`), causing syntax errors, such as _Cannot use import statement outside a module_.

This happens when Node is started into a directory built from TypeScript sources into a set of `.js` & `.d.ts` files.

## To Reproduce

Reproduction repository available here:
https://github.com/franky47/fastify-autoload-65

## Expected behavior

Since Node.js cannot understand type definition files, and they contain no runtime code, I believe the extension `.d.ts` should be ignored, even when `includeTypeScript` is true.

## Your Environment

- *node version*: 13.7.0
- *fastify version*: 2.11.0
- *fastify-autoload version*: 1.2.0
- *os*: macOS
