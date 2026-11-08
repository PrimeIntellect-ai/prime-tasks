BUG | vitest v3 | `There was an error when mocking a module` when `mockNuxtImport` with existing `vi` import
### Environment

- Operating System: `Linux`
- Node Version:     `v23.5.0`
- Nuxt Version:     `3.15.4`
- CLI Version:      `3.21.1`
- Nitro Version:    `2.10.4`
- Package Manager:  `pnpm@9.15.5`
- Builder:          `-`
- User Config:      `-`
- Runtime Modules:  `-`
- Build Modules:    `-`


### Reproduction

https://github.com/nuxt/test-utils/pull/1128

### Describe the bug

when not using vitest globals and importing and using `vi` and `mockNuxtImport` vitest 3 fails with:

```
Error: [vitest] There was an error when mocking a module. If you are using "vi.mock" factory, make sure there are no top level variables inside, since this call is hoisted to top of the file. Read more: https://vitest.dev/api/vi.html#vi-mock
Caused by: TypeError: Cannot read properties of undefined
```

### Additional context

_No response_

### Logs

```shell-script

```

### Additional contract requirements

- The mock transform must always emit syntactically valid ES module code, including when the source already imports `vi`.
- When the source does not import `vi`, the transform adds a single `import { vi } from 'vitest'`. When the source already imports `vi`, that import is preserved and not duplicated.
- The transform replaces the `mockNuxtImport(...)` call with a `vi.mock(...)` registration for the mocked module, preserving the mocked export name.
