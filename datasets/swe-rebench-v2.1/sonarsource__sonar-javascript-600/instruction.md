Improve UseOfEmptyReturnValueCheck: ignore await
**Rule key:** S3699 (UseOfEmptyReturnValueCheck)

Hi,

We currently have false positives with the **UseOfEmptyReturnValueCheck** rule when using the `await` keyword.

For instance:

```js
const doSomethingAsync = async () => {
  // ...
}

await doSomethingAsync() // UseOfEmptyReturnValueCheck error
```

I think that the `async` keyword should be excluded from the check.
