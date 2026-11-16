name conflict between imports and underscore prefixed function-scoped properties
**Describe the bug**
This issue is related to #2211
This is an additional case where the same problem occurs.
When an imported name is used in a function within a function, it seems that the problem that the variable name is not changed occurs.

**Input code**
```js
// import Bar from './Bar'; has the same issue.
import { bar } from './Bar';

const makeX = (props) => {
  const _bar = props.bar;
  const { list } = _bar;

  return list.map(() => bar);
};
```

**Output**

```js
"use strict";
var _bar = require("./Bar");
var makeX = function(props) {
    var _bar = props.bar;
    var list = _bar.list;
    return list.map(function() {
        return _bar.bar;
    });
};

```

**Config**

```json
{
  "module": {
    "type": "commonjs"
  },
  "jsc": {
    "parser": {
      "syntax": "ecmascript"
    },
    "target": "es5"
  }
}
```

**Expected behavior**
Generated import names should not conflict with function variables.

**Version**
The version of @swc/core: 1.2.90

### Additional contract requirements

- Running the hygiene pass (`hygiene_with_config` with the default configuration) on a module in which a module-level `var _bar` is referenced from inside a function that declares its own `var _bar` (declared before use), the two bindings must end up with different names in the output.
- After the pass, a reference to `_bar` inside the nested function must still resolve to the module-level binding, and `_bar` references in the enclosing function must still resolve to that function's own variable.
