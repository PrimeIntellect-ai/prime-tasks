Assigning directly to an array by index does not change array length
## Expected behavior

When assigning directly to an array position, the array length should be updated, a la the native JavaScript array behavior. Any components depending on the array (for example, iterating over its items) should be re-rendered.

**Example of index assignment with a native Array**

```
const arr = [];
arr[0] = 'foo';
arr.length; // 1
arr[6] = 'bar';
arr.length; // 7
```

## Observed behavior

When assigning to an array position on a proxy store, the length is not updated, and dependent components do not re-render. However, an update notification is sent to `subscribe`.

Reproduction: https://codesandbox.io/s/valtio-array-length-bug-kl8d2?file=/src/App.js

Uncomment line 44 to "fix" the problem manually by assigning the correct array length. This triggers the component re-render, too.

Observe also that the `subscribe` callback, when it logs the current proxy state, shows the new third item present but the length is still `2`.
