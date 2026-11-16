Experimental splitting: not removing the import statement
### Describe the bug

See this [snapshot](https://github.com/TanStack/router/blob/main/packages/router-plugin/tests/code-splitter/snapshots/imported.tsx) for the [`imported.tsx`](https://github.com/TanStack/router/blob/main/packages/router-plugin/tests/code-splitter/test-files/imported.tsx) test file compiled file when using the `experimental.enableCodeSplitting` flag.

In the compiled output, a single import string-literal is being left behind.

```tsx
const $$splitLoaderImporter = () => import('tsr-split:imported.tsx?tsr-split');
import { lazyFn } from '@tanstack/react-router';
const $$splitComponentImporter = () => import('tsr-split:imported.tsx?tsr-split');
import { lazyRouteComponent } from '@tanstack/react-router';
import { createFileRoute } from '@tanstack/react-router';
import '../shared/imported'; // <- this one here
export const Route = createFileRoute('/')({
  component: lazyRouteComponent($$splitComponentImporter, 'component'),
  loader: lazyFn($$splitLoaderImporter, 'loader')
});
```

Having this in means, that the code isn't really being split out during the build process, since the entire file is being imported anyway.

An edge case to be considered however is that sometimes a user may intentionally (on the user-side) make such an import (like how `react-i18next` recommends the [setup](https://react.i18next.com/guides/quick-start#configure-i18next) to be done).

As such, the code elimination should only evaluate removing import string-literal statements if they are about components or loaders.
