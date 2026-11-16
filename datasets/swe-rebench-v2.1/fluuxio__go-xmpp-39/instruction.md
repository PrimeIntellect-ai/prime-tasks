No method to close Connection
There is no way to close session or client connection.

### Additional contract requirements

- Add a public method `Disconnect()` on `*Client` in package `xmpp` that closes the client connection.
