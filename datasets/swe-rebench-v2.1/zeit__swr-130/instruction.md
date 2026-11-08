softRevalidate error when no fetcher or default fetcher provided.
I'm trying to use swr to read in a value without a fetcher, since I know the fetch was started elsewhere (tab one).

Using the [provided demo](https://codesandbox.io/s/eager-field-zs7v8), tab between _one_ and _three_.  Eventually you'll see the following error:

```
index.js:1375 Result Error TypeError: fn is not a function
    at use-swr.js:213
    at softRevalidate (use-swr.js:321)
```
keyFunction type declaration incorrect
keyFunction's type is [HIDDEN], it can't accept a null return value or array value, which is conflict with example

### Additional contract requirements

- A key function may return `null` to disable fetching without causing a type or runtime error.
- A key function may return an array, which is handled as an array key; its elements are passed to the fetcher as separate arguments.
- Revalidation when no fetcher is available must not produce an error or make a request.
