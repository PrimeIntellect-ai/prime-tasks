[bug] ImportDeclarations with importKind: "type" do not account for local specifiers
**input**

```js
import type { Scroll as GridScroll } from '../Grid';
import type { Scroll } from './types';
```

**output**

```js
import { bpfrpt_proptype_Scroll } from '../Grid';
import { bpfrpt_proptype_Scroll } from './types';
```

Which of course is a clash of identifiers and results in
> [!] (commonjs plugin) SyntaxError: Identifier 'bpfrpt_proptype_Scroll' has already been declared (238:9) in /Users/mateuszburzynski/Desktop/react-virtualized/source/List/List.js

**NOTE**
I'm reporting it but also preparing a fix right now.

### Additional contract requirements

- For imports of Flow types from distinct modules, generated validators must reference the generated prop-type export from the module that supplied the type, even when the type has a local alias. Distinct imported types must not clash merely because their generated prop-type exports share a name.
