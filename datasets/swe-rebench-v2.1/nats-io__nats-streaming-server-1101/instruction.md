STAN authentication problem when connecting with NKeys
Hello!

We're setting up a NATS and STAN cluster. The STAN cluster needs to connect to our NATS cluster, obviously. But now I'm having trouble to authenticate, when connecting the STAN cluster to the NATS cluster.

We are using NKeys for authentication, but I can't seem to figure out how to configure STAN correctly.

The NATS auth configuration looks like this:
```
authorization: {

  ...

  STAN: {
    publish: ">"
    subscribe: ">"
  }

  users: [
    ...
    //STAN-SERVER
    {nkey: UDNBXF3RNSPSZZIACU42AQDV7XF6ZLKUSADUGEH3F2HQW3E2PEWN6JIK, permissions: $STAN}
   ...
  ]
}
```

And the STAN config:
```
streaming {
      ...
      credentials: /etc/stan-creds/stan.creds
      ...
    }
```

The file stan.creds contains the NKey seed, corresponding to the user public key for above. I tried various formats, for example
```
SUAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

OR
```
-----BEGIN USER NKEY SEED-----
SUAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
------END USER NKEY SEED------
```

In STAN I get the following (obvious) error:
```
[1] 2020/10/05 15:50:51.725194 [FTL] STREAM: Failed to start: nats: Authorization Violation
```
And in NATS (just the empty quotes after Nkey):
```
[6] 2020/10/05 15:52:24.788799 [ERR] 10.244.0.99:50458 - cid:145 - authentication error - Nkey ""
```

Is STAN not supporting NKey authentication or am I doing something wrong?

Thanks in advance

### Additional contract requirements

- The streaming server configuration accepts a string option named `nkey_seed_file`
  whose value is the path to a file containing the NKey seed (private key) used to
  authenticate the server's connection to the NATS server.
- The corresponding public option field is `Options.NKeySeedFile` (string).
- The seed file may contain the seed either as a bare seed string or wrapped in
  `-----BEGIN USER NKEY SEED-----` / `------END USER NKEY SEED------` markers.
- A non-string value for `nkey_seed_file` is a configuration error.
