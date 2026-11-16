Add support for dynamic imports to the reflection
Currently we support static imports:

```ts
import x, {y, a as z } from 'module';
```

And need to add support for dynamic imports:

```ts
const { z } = await import('module');
```

### Additional contract requirements

- Parsing the dynamic import form `const { z } = await import('module');` must succeed and register the dynamic import in the module's imports, with the module specifier (`'module'`) as its source, using the same source value as static imports.
