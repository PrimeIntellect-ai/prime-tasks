Unable to use `onAbort` more that one time
Hello, thank you for the library!

According to the [documentation](https://farfetched.pages.dev/api/utils/on_abort.html), for the actual interruption of a request, we should pass the abort controller's signal to a lower level in the handler or effect properties. However, if we don't use createJsonQuery and attempt to apply onAbort to our effects or handlers more than once, the code simply stops working with an onAbort call is not allowed error.

Easy example:
```
const someFx = createRequest({
    endpoint: '/',
    method: 'GET'
})

const queryA = createQuery({
    async handler() {
        const abortController = new AbortController()

        console.log('called')

        onAbort(() => abortController.abort())

        console.log('executed')

        return someFx({ __: { signal: abortController.signal } })
    }
})

const queryB = createQuery({
    async handler() {
        const abortController = new AbortController()

        console.log('called')

        onAbort(() => abortController.abort())

        console.log('fails here')

        return someFx({ __: { signal: abortController.signal } })
    }
})
```

In this example, onAbort in queryA works well, but onAbort in queryB fails.
