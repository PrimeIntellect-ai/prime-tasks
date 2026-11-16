Can't use ESM with `jsc.paths`
### Describe the bug

Hey folks,

I've come into a bit of a pickle. Node 19 [drops support for `es-module-specifier-resolution`](https://stackoverflow.com/questions/74660824/nodejs-v19-drops-support-for-es-module-specifier-resolution-node-which-makes-i), which I have been using to support extension-less imports in my ESM codebase.

I realized this makes it impossible for me to continue using `jsc.paths` in my TypeScript project, as `ts` files automatically have their extensions removed, yet if I use `js` as an extension, SWC can't find the path and doesn't transform the import.

## Example

```
"paths": {
    "@my/pkg": ["libs/pkg/src/index.ts"]
}
```

results in:

```
import { fn } from 'libs/pkg/src/index';
```

and

```
"paths": {
    "@my/pkg": ["libs/pkg/src/index.js"]
}
```

results in:

```
import { fn } from '@my/pkg';
```



### Input code

```typescript
import { fn } from '@my/pkg';
```


### Config

```json
{
  "module": {
    "type": "es6"
  },
  "jsc": {
    "baseUrl": ".",
    "target": "es2020",
    "parser": {
      "syntax": "typescript",
      "decorators": true,
      "importMeta": true
    },
    "transform": {
      "legacyDecorator": true,
      "decoratorMetadata": true
    },
    "keepClassNames": true,
    "paths": {
      "@my/pkg": ["libs/pkg/src/index.ts"],
    }
  }
}
```


### Playground link

_No response_

### Expected behavior

I think that SWC should provide a similar mechanism to how [TypeScript supports ESM](https://2ality.com/2021/06/typescript-esm-nodejs.html#typescript), where TS files can be imported as JS (i.e. `jsc.paths` should find and transform the path appropriately).

Better yet, now that you [_can_ import `ts` files in TS](https://github.com/microsoft/TypeScript/issues/53316), what I really wish is that you could just always use `ts` extensions for everything and SWC would be smart enough to know to replace them with `js` in the transpiled code instead of just removing the extension.

### Actual behavior

Right now, SWC defaults to removing TS extensions unless you manually import TS files as JS (which luckily TS supports), however, this breaks down when using `jsc.paths` as described above. Starting in Node 19, this will result in un-runnable code without a custom loader.

### Version

1.3.77

### Additional context

_No response_

### Additional contract requirements

- An exact `jsc.paths` entry (a key that contains no `*`) rewrites the import specifier to the mapped path resolved against `baseUrl`, even when the mapped file does not exist on disk.
- When the mapped path ends in `.js`, the rewritten specifier keeps the `.js` extension. For example, with `"@my/pkg": ["libs/pkg/src/index.js"]`, `import { fn } from '@my/pkg'` becomes `import { fn } from "./libs/pkg/src/index.js"`.
- When the mapped path ends in `.ts`, the rewritten specifier drops the TypeScript extension. For example, with `"@my/pkg": ["libs/pkg/src/index.ts"]`, `import { fn } from '@my/pkg'` becomes `import { fn } from "./libs/pkg/src"`.
