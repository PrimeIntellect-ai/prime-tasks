Request to the matrices are send even when no payload
When calling `shutdown` on `MeterProvider` after creating it with purely default providers using `(new MeterProviderFactory())->create()` it will send a request to the matrices endpoint, even though there has been no meters registered.

This can of course be solved in the application by not calling `shutdown` when the class haven't been used, however this is not the same way `TracerProvider` works.
That one only sends a request if there actually is something to send.

### Additional contract requirements

- When metrics are available at shutdown, the reader must still export them.
