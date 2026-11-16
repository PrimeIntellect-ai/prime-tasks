useLocalStorage does not update value when key change
**What is the current behavior?**

When the key of the local storage change with the same hook, the initialisation is not run.

**Steps to reproduce it and if possible a minimal demo of the problem.

https://codesandbox.io/s/practical-almeida-13o7o?file=/src/App.tsx

**What is the expected behavior?**

When the key change, the initial value is set

**A little about versions:**

see code sandbox

### Additional contract requirements

When the key changes on an existing hook instance, the returned value must be initialized for the new key rather than retained from the previous key. If the new key already has a value in local storage, that stored value is used in preference to the supplied initial value.
