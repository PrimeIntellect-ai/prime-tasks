Runtime issue with named export overrides


**Describe the bug**
Based on https://github.com/swc-project/swc/issues/1714

Valid JS is generated, but at runtime if the override is not the same (identity-wise) as the export from `*` the code won't load.

**Input code**
```
import { customRender } from './customRender';

// re-export everything
export * from '@testing-library/react';

// override render method
export { customRender as render };
```

**Config**

```json
{
  "sourceMaps": true,
  "jsc": {
    "parser": {
      "syntax": "typescript",
      "tsx": true,
      "dynamicImport": true
    },
    "transform": {
      "react": {
        "runtime": "automatic",
        "refresh": true
      },
      "hidden": {
        "jest": true
      }
    }
  },
  "module": {
    "type": "commonjs"
  },
  "env": {
    "coreJs": 3,
    "mode": "usage"
  }
}
```

**Expected behavior**
The transpilation should respect the behaviour that the named exports can override the wildcard exports.
e.g. [Babel REPL](https://babeljs.io/repl#?browsers=node%2014&build=&builtIns=false&corejs=3.6&spec=false&loose=false&code_lz=JYWwDg9gTgLgBAbzgYwK4GcYRAJQKYB2AJnlHAL5wBmU2cA5AHQD0am2-xp9A3AFB9mzOFDwBaPAA9IsOHgBupAJ4wAFsAIBzPlJnwAVNVogGAARh5MGzWIA2wAEZQAhlCXNRz5DF4ChcCEUoKGASEUISMhA8NQgiHWloeCQ2LFwI0jhndHCuMnJ-IA&debug=false&forceAllTransforms=false&shippedProposals=false&circleciRepo=&evaluate=false&fileSize=false&timeTravel=false&sourceType=module&lineWrap=true&presets=env,react&prettier=false&targets=Node-14&version=7.14.1&externalPlugins=) [HIDDEN]

**Version**
The version of @swc/core: 1.2.77

**Additional context**
This code should have this behaviour too:
```
export { customRender as render } from './customRender';

// re-export everything, but keep named 'render' exported above
export * from '@testing-library/react';
```

### Additional contract requirements

- When a name is both explicitly exported by the module and provided by an `export *` from another module, the explicit export must be the binding that importers of the module observe, regardless of which statement appears first in the module, and the module must load at runtime.
