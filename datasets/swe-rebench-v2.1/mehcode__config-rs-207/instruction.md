Asynchronous config source
I was wondering if there is a broader need for what can be called asnychronous config source?

At my company we use dedicated configuration service that can be asked for config for given application via HTTP. I believe there are also other solutions that use network to retrieve configuration (for instance a database source).
While implementing `Source` trait for our configuration service I had to use blocking HTTP client. One may say this is not a problem since configuration refresh is not a frequent action. However, when you try to squeeze every ounce of performance from your application or you are using single-thread scheduler this can hurt. Also, in our specific case config is expected to be read by applications in real-time almost, so refresh should be quite frequent.

While implementing blocking HTTP source I encountered a problem with blocking `Client` from `reqwest` crate, since blocking client tries to start a Tokio runtime underneath and use non-blocking implementation, but block on it with `tokio::block_on`. Which basically panics, since if you are using tokio runtime, you are not allowed to set up another runtime inside. There are workarounds for it like:
* push config download out of runtime (but you can have hard time refreshing it then)
* use another library to perform blocking call (which can hurt on single-thread sheduler and makes this crate less friendly to use)

For those reasons I though about asynchronous configuration source.

I am afraid however that it would be hard to make it both easy to use, performant and backwards-compatible. I would drop the latter if I were to choose.

Since I come from .NET world I am quite used to `IConfiguration` introduced by .NET Core. This crate resembles it to some extent.
[HIDDEN]

What is your take on that? And, **is this crate maintained**? It looks really nice, but last comitts are quite old. I would be happy to make a pull request with aforementioned changes, but I wouldn't like to do work that would hang in a PR for eternity.

### Additional contract requirements

- Configuration can be collected from an asynchronous source.
- Registering a source does not collect its values; collection is deferred until the builder is asked to produce a configuration.
- An asynchronous build can combine asynchronous and synchronous sources.
- Asynchronous source functionality does not require or assume a particular executor/runtime.
- The public asynchronous source interface is named `AsyncSource`, is exported from the crate root, and provides an asynchronous `collect` operation that yields configuration key/value data. Implementations are written with the `async-trait` crate's `#[async_trait]` attribute.
- Adding an asynchronous source is done with `add_async_source`; after that the builder's `build` is asynchronous and yields the built configuration. Asynchronous builds also collect any synchronous sources registered on that builder.
