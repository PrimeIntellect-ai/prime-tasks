Need more data in the ClientHello struct to choose best cert/key for connection
**Checklist**
* [x] I've searched the issue tracker for similar requests

**Is your feature request related to a problem? Please describe.**
Certificate selection using ResolvesServerCert and documentation for Acceptor seem to not contain enough information in order to properly choose the best certificate for a client.

**Describe the solution you'd like**
It looks like all of the solutions in the documentation point to getting a ServerConfig from a function that takes a ClientHello struct.

However ClientHello does not seem to contain enough information about what client capabilities are present during the handshake.

It is my understanding that in order to properly choose the correct keys, we would need to have access to (at least) the list of client supported NamedGroup's in order to choose the correct cert/key pair from a list of potential ones.

### Additional contract requirements

- Expose the client-advertised named groups through a public `ClientHello::named_groups(&self) -> Option<&[NamedGroup]>` accessor. Return `Some` with the advertised groups when the extension is present, and `None` when it is absent.
