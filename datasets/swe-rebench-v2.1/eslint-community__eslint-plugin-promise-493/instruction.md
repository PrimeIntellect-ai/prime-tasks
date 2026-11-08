`promise/always-return` should not be reported when process exits
### Description

If I do `process.exit(0);` in a .then callback no return value should be expected from the callback as after the exit the rest of the code is unreachable.

### Steps to Reproduce

```ts
 void fetch(
     'my-url',
     {
         method: 'POST',
         headers: {
             // eslint-disable-next-line @typescript-eslint/naming-convention
             'Content-Type': 'application/json'
         },
         body: JSON.stringify({...})
     }
     // eslint-disable-next-line promise/always-return (this should not be needed)
 ).then(() => {
     task.stop();
     process.exit(0);
});
```

**Expected behavior:** not to report issue when process exists

**Actual behavior:** issue reported

### Versions

[Please fill this in if you are submitting a bug report]

- Node version: 21.6.1
- ESLint version: ^8.23.1
- eslint-plugin-promise version: ^6.0.0
