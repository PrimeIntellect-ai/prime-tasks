Missing `Future` publisher
I've tried to port [GRDBCombine](https://github.com/groue/GRDBCombine) to OpenCombine and it seems like the biggest missing piece there is a lack of the [`Future`](https://developer.apple.com/documentation/combine/future) publisher. Just adding it as a separate issue here for now to hopefully bump its priority on a possible OpenCombine roadmap 🙂

### Additional contract requirements

- Provide a public `Future<Output, Failure>` publisher, where `Failure: Error`, with a public `Promise` type alias of `(Result<Output, Failure>) -> Void` and the initializer `init(_ attemptToFulfill: @escaping (@escaping Promise) -> Void)`.
- Invoke the initializer’s closure immediately. The first call to its promise determines the single result: a success emits its value and finishes, and a failure emits that failure. Subsequent promise calls have no effect. Subscribers receive the result whether they subscribe before or after the promise is fulfilled.
