More flexible server.address configuration (file descriptor, PROXY...)
### Description


First of all, thank you for this nice project!

I would like to deploy authelia using systemd sockets (systemd opens the privileged port and handles it to authelia).
Looking at the code, it seems that `server.address` currently supports `tcp(4|6)` and `unix` (with `?umask`).

It would be nice if listening to file descriptor was possible.

### Use Case


Better integration with systemd (so that the authelia service does not need to bind on any socket).

### Details


Instead of reinventing the wheel, maybe something like https://github.com/AGWA/go-listener/ could be used. It allows to create a `net.Listener` by parsing a string. For instance:
```
tcp:80  // all interfaces, port 80
tcp:0.0.0.0:80 // all ipv4, port 80
tcp:[::1]:80 // all ipv6, port 80

unix:/path/to/socket // unix socket (umask is not supported yet, maybe upstream would accept a PR)

fd:4 // listen on file descriptor 4 - which can be passed by systemd
```

Those listeners can also be wrapped, by prepending them. For instance the `tls` subpackage allows:
```
tls:/folder/with/certificates/:tcp:443 // will get the key and certificate from the folder
tls:/path/to/certificate_file:tcp:443 // will get the key and certificate from the file
tls:example.com:tcp:443 // will use lets encrypt to get the certificate
```

Another (currently) missing feature of `go-listener` is client certificates. I could also look into implementing them upstream or in a dedicated package.

## Example of the proposed change on the config

Current
```yml
server:
  address: tcp://:9091
  tls:
    key: "/folder/with/certificates/key"
    certificate: "folder/with/certificates/certificate"
    client_certificates: ["/folder/with/client/cert"]
```
Proposed:

```yml
server:
  listener: tls:/folder/with/certificates/:tcp:9091
  client_certificates: ["/folder/with/client/cert"]
```

Other examples:
```yml
server:
  listener: tls:example.org:fd:4
```

## Contributing

I would be willing to craft a PR, if you think that this approach sound sensible.

### Documentation


_No response_

### Pre-Submission Checklist


- [X] I agree to follow the [Code of Conduct](http://www.authelia.com/code-of-conduct)

- [X] I have checked for related issues and checked the documentation

### Additional contract requirements

- An address with the `fd` scheme identifies an inherited file descriptor by its number, written as the host of an
  `fd://` address, for example `fd://4` refers to descriptor 4.
- An `fd://` address whose descriptor is not a number (for example `fd://abc`) is rejected as an invalid address.
- Creating a listener from a valid `fd://` address returns a listener that accepts connections on the socket that is
  open on that descriptor, and the listener reports the same local address as that socket.
- The server listener address (`server.address`) accepts an `fd://` address as a valid scheme, so a configuration
  using one passes server address validation.
