client Transport is not exported
The doc comment for suggests this function should be exported, but it is not:

```
// Transport method returns `*http.Transport` currently in use or error
// in case currently used `transport` is not a `*http.Transport`.
[HIDDEN]
```

My use case here is I'm trying to integrate otelhttp, so I would like to do
```
client.SetTransport(otelhttp.NewTransport(client.Transport()))
````
to wrap the resty transport to inject the span context into the outbound request, but since the transport function is not exported, this won't work.

### Additional contract requirements

- Expose `Client.Transport() (*http.Transport, error)` as a public method. It returns the current transport when that transport is an `*http.Transport`, and returns an error otherwise.
