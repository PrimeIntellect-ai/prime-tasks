Abort createAsyncThunk Uncaught (in promise)
I found a bug (or a feature...), the promise.abort console a Uncaught (in promise) when the promise wasn't actually called due to condition in createAsyncThunk.

``` typescript
    // same probleme with useEffect
    useLayoutEffect(() =>
    {
        const promise = dispatch(getData());

        return () =>
        {
            promise.abort('Unmount on pending');
        };
    }, [dispatch]);
```

```typescript
export const getData = createAsyncThunk<Data, undefined, { state: RootState }>(
    'apiData/getData',
    async () => DataServices.getData(),
    {
        condition: (_, { getState }) =>
        {
            const { data } = getState();
            return data.getDataStatus !== Status.Fulfilled;
        },
    },
);
```

If my condition return false and then we don't do the cycle of createAsyncThunk, my promise exist and do the abort, but the abort console redux-toolkit.esm.js:1345 Uncaught (in promise) {name: "AbortError", message: "Unmount on pending"}.

I have other way to handle this but this way is cleaner. Is it "normal" and I should just handle myself the condition and unmount in the useEffect or is it a bug and the abort should not be triggered or console the Uncaught ?

### Additional contract requirements

- If a thunk invocation is skipped because its `condition` returns `false`, calling `abort()` on its returned promise must be a no-op and must not cause an unhandled rejection.
