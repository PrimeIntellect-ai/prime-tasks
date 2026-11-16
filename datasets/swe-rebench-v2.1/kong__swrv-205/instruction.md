`isValidating` true when key is falsey
Hey there,

it seems like the `isValidating` flag is true even if no request is currently happening (or has happened). This feels like a bug.

```js
const { isValidating } = useSWRV(() => null)

// `isValidating` is `true` even though no fetch is happening
```

Thank you!
