`no-throw-statements` Allow in `catch` callbacks
## Suggestion

```ts
somePromise.catch(() => {
  throw new Error("Some error");
});
```

### Additional contract requirements

When configured to allow throws used to reject promises, a throw statement inside a Promise `catch` callback is allowed.
