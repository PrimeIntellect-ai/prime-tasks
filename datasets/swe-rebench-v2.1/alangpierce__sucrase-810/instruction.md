Incorrect elision of `import {}` with TS transform disabled
As I was working on import elision behavior, I noticed a bug when handling this code snippet:
```ts
import {} from "./a";
```
The expected behavior is:
* With the TS transform enabled, the import is elided, so `./a` is never evaluated at runtime. [TS playground link](https://www.typescriptlang.org/play?#code/FASwtgDg9gTgLgAgN4F8EDMZTAgRAOgHoBDXAbmCA). This happens because "all imports are type-only" is vacuously true.
* With the TS transform disabled, the import is preserved, so `./a` is evaluated at runtime. This is because import elision is a TS feature, so in plain JS there's no reason to do it.

Sucrase handles the first case correctly, but when the TS transform is disabled, it incorrectly removes the import, so this issue tracks the fix for that.
