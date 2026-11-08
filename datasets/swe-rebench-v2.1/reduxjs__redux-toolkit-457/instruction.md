createAsyncThunk cannot pass non-serializable arg
I try to use `createAsyncThunk` with non-serializable object like:

```ts
export const roundAsync = createAsyncThunk(
  "someAsync",
  ({ api }: { api: ApiClient }) => {
    return api.apiAction()
  }
)
```

and I got error

```
index.js:1 A non-serializable value was detected in an action, in the path: `meta.arg.api`. Value: ApiClient {}
Take a look at the logic that dispatched this action:
```

I found this issue ignored `meta.args` by default
https://github.com/reduxjs/redux-toolkit/pull/410

but maybe `createAsyncThunk` fire `meta.arg`

Additionaly, I try  customize `serializableCheck.ignoredPaths` option, I cannot resolve this too.
[HIDDEN]
https://github.com/reduxjs/redux-toolkit/blob/a1e8becbb2e4653d721bdc1d2363a45562c526a2/src/serializableStateInvariantMiddleware.ts#L157-L162

### Additional contract requirements

- When checking dispatched actions, non-serializable values beneath `meta.arg` are ignored by default. This exemption applies only to that action path; other action paths continue to be checked.
- Callers can choose which action paths to exclude with the `ignoredActionPaths` option of `createSerializableStateInvariantMiddleware`. Supplying an empty list disables the default exemption.
