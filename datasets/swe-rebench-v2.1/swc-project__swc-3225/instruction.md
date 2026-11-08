Does not transform `&&=` “logical AND assignment” operator
### Describe the bug

(similar to #1788) swc does not transform the [Logical AND assignment](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Logical_AND_assignment) operator (`&&=`).

### Input code

```typescript
const swc = require('@swc/core');
swc.transformSync(`a ||= b`, {});  // a || (a = b);
swc.transformSync(`a &&= b`, {});  // a &&= b;
```


### Config
N/A


### Expected behavior

The `&&=` operator is transformed by SWC, like the `||=` and `??=` operators are.

### Actual behavior

The `&&=` operator is left untransformed.

### Version

1.2.127

### Additional context

_No response_
