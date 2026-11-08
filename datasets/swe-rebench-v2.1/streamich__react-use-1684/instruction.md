useStateWithHistory doesn't pass current value to callback style setState
**What is the current behavior?**

Using `useStateWithHistory`'s callback style `setState` will receive no arguments.

```
const [state, setState] = useStateWithHistory(0);
setState(val => val + 1); // val is undefined
```

**Steps to reproduce it and if possible a minimal demo of the problem. Your bug will get fixed much faster if we can run your code and it doesn't have extra dependencies other than `react-use`. Paste the link to your [JSFiddle](https://jsfiddle.net) or [CodeSandbox](https://codesandbox.io) example below:**

See example above.

**What is the expected behavior?**

Expected callback style `setState` to receive the current value as the first argument.

**A little about versions:**
- _OS_: NA
- _Browser (vendor and version)_: All (Chrome)
- _React_: 17
- _`react-use`_: 13.3.0
- _Did this worked in the previous package version?_ No
