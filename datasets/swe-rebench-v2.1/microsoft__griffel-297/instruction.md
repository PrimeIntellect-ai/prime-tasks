Passing empty string to any property creates "void 0" style when build-time optimizations are enabled
When build-time optimizations are enabled (both babel and webpack plugins), passing an empty string as the value of a CSS property generates a `void 0` style that can cause errors when inserted into the stylesheet in certain environments.

For example, the code:

```ts
import { makeStyles } from '@griffel/react';

export const useStyles = makeStyles({
  test: {
    color: '',
  },
});
```

Produces output:

```js
import { __styles } from '@griffel/react';
export const useStyles = /*#__PURE__*/__styles({
  "test": {
    "sj55zd": "fsj55zd"
  }
}, {
  "d": [void 0]
});
//# sourceMappingURL=useTestStyles.js.map
```

This is the error being thrown for a similar style in an app:

<img width="597" alt="image" src="https://user-images.githubusercontent.com/7798177/207987221-7548b626-6f08-4ad9-b1a1-48e19e0e08ec.png">

A possible solution would be to ignore rules like this, similar to how we ignore `undefined` values being passed to a property.

### Additional contract requirements

- A property whose value is an empty string must be ignored: no CSS rule (and in particular no `void 0`/`undefined` entry) may be produced for it, both when styles are resolved at runtime and when they are resolved by the build-time transforms.
