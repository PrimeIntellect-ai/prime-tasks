[import/default] - false negative for react-test-renderer
I'm doing this:
```
import reactTestRenderer from 'react-test-renderer';
```

Getting this:
```
No default export found in imported module "react-test-renderer". eslint (import/default)
```

Using these types: https://github.com/DefinitelyTyped/DefinitelyTyped/blob/master/types/react-test-renderer/index.d.ts

And I have `esModuleInterop` in my tsconfig, so this should not throw error (thanks to https://github.com/import-js/eslint-plugin-import/pull/1689)
