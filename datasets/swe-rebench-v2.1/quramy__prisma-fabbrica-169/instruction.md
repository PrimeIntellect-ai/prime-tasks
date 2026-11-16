Import paths in generated code without transpilation are different across Windows and Linux
When the setting `noTransplie` is set to `true`, part of the import path is escaped `\\` on Windows vs on Linux which uses `/`.

Example:

`Windows`
```javascript
import type { User } from "./..\\..\\prisma-client\\dist\\client";
```
`Linux`
```javascript
import type { User } from "./../../prisma-client/dist/client";
```

This results in issues with version control when the code is complied across operating systems.

### Additional contract requirements

- Add a public function `getClientModuleSpecifier(clientGeneratorOutputPath: string | undefined, outputDirname: string): string` in `packages/prisma-fabbrica/src/getClientModuleSpecifier.ts`. It returns the module specifier used to import the generated Prisma Client:
  - `"@prisma/client"` when `clientGeneratorOutputPath` is falsy, including `undefined` and the empty string, or when the normalized client path ends with `node_modules/@prisma/client`.
  - Otherwise a relative POSIX module specifier (for example `"../prisma-client"`), using `/` separators and normalized so that it does not begin with `./`.
  - Windows (`\`) and POSIX (`/`) separators in either input are accepted and normalized to POSIX.
- When the generator runs with `noTranspile` enabled, the generated code must import the Prisma Client using this POSIX module specifier, so the generated import is identical on Windows and Linux.
