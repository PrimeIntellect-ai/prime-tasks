Plug.Static.InvalidPathError, no debugging information provided
Hello,
We have a reccuring error catched by our Sentry, with `Plug.Static` raising a `Plug.Static.InvalidPathError`.
Unfortunately, in the stack information given, the URL at the origin of the problematic request is not specified, making it difficult to understand what is happening.
Here is an example Sentry output:
![image](https://user-images.githubusercontent.com/15341118/167844641-8b46efd3-42a9-4b8c-8b60-57f06bf5390d.png)

Is there a way I'm missing to get this information?
Should the error be enriched with some information about the static asset being requested?
Thanks

### Additional contract requirements

When `Plug.Static` raises `InvalidPathError` for an unsafe asset request, its diagnostic message must include the original request path.
