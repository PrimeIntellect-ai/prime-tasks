🚀 Feature: Remove sourcemap: true from tsup.config.ts
### Bug Report Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

For many years now, I've tried to publish sourcemaps in all projects I publish to npm. The idea was that it would be nice for folks debugging through the code to see the source, including pre-transpiled syntax sugar and TypeScript types.

More recently I've seen packages move away from sourcemaps:

* https://github.com/typescript-eslint/typescript-eslint/issues/9352: noting that sourcemaps add a lot to the typescript-eslint published output size, and aren't always useful or even correct
* https://github.com/JoshuaKGoldberg/ts-api-utils/issues/573 -> https://github.com/JoshuaKGoldberg/ts-api-utils/pull/576: similarly, removing them from `ts-api-utils` dropped the built size a good bit

I'm personally now in favor of removing sourcemaps from the default `tsup.config.ts` in CTA and its templates. But just to be safe, I'll leave this issue with `status: in discussion` for a while. If anybody knows of reasons to do this or not to do this, please post! 🙂

### Additional Info

🎁

### Additional contract requirements

- Generated `tsconfig.json` files must omit the `sourceMap` compiler option.
- Generated tsup configuration files must omit the `sourcemap` option.
