Calling got.stream via options flag with got()
Looking through the source, I see `got.stream` [HIDDEN], with the various methods added one level down.

I'd love to be able to do something like:

```
got(url, {
  stream: true
})
```

[HIDDEN] Something similar is fine too.

The use case is to have got wrapped so each request has the same configurable retries and timeout specs.

### Additional contract requirements

- When `got(url, {stream: true})` is called, it must return a stream for the response rather than the usual promise-based result.
