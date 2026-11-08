Time duration for `handshake_first` option is not respected for leafnodes
### Observed behavior

According to this [ADR](https://github.com/nats-io/nats-architecture-and-design/blob/main/adr/ADR-40.md) passing a time duration for the `handshake_first` option, makes the server backward compatible because after the timeout the server is supposed to use the standard TLS flow.

This works for standard connections (from clients) but not for leafnodes.
If the leafnode doesn't declare the `handshake_first` field in the `remotes` section, its connection will be never accepted by the server

I'm able to connect to my server using `nats-cli` with or without the `--tlsfirst` flag (because of the timeout) but the leafnode can connect to the server only if it use the field in the remote section.

### Expected behavior

A leafnode connection without `handshake_first` is accepted (standard TLS flow) after the initial timeout

### Server and client version

nats-server: v2.10.18 (both server and leafnode)
nats-cli: 0.1.5

### Host environment

_No response_

### Steps to reproduce

Main server has this configuration
```
TLS = {
  cert_file: $CERT_FILE
  key_file: $KEY_FILE
  ca_file: $CA_FILE
  verify_and_map: true
  timeout: 2
  handshake_first: 500ms
}

tls : $TLS

leafnodes {
    port: 20023
    tls: $TLS
}
```

The leafnode has this one
```
TLS = {
  cert_file: $CERT_FILE
  key_file: $KEY_FILE
  ca_file: $CA_FILE
  verify_and_map: true
  handshake_first: 500ms
}

tls : $TLS

leafnodes {
  remotes: [
    {
      url: $SERVER
      tls {
         cert_file: $CERT_FILE
         key_file: $KEY_FILE
         ca_file: $CA_FILE
         handshake_first: true
      }
      account: $MY_ACCOUNT
    }
  ]
}
```

In this case works, but if I remove the `handshake_first` from `remotes` section it doesn't

```
TLS = {
  cert_file: $CERT_FILE
  key_file: $KEY_FILE
  ca_file: $CA_FILE
  verify_and_map: true
  handshake_first: 500ms
}

tls : $TLS

leafnodes {
  remotes: [
    {
      url: $SERVER
      tls {
         cert_file: $CERT_FILE
         key_file: $KEY_FILE
         ca_file: $CA_FILE
      }
      account: $FILEWAVE_ACCOUNT
    }
  ]
}
```
