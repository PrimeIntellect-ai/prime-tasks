Add flag to set the account server url for `nsc push`
This would avoid having to hardcode an ip into the jwt when pushing or modifying /etc/hosts to the public ip in case the machine has not been deployed yet.

Instead of

```sh
nsc edit operator --account-jwt-server-url http://127.0.0.1:9090/jwt/v1/
nsc edit operator --account-jwt-server-url http://external-nats-account-server:9090/jwt/v1/
nsc push -A
```

Do for example:

```
nsc push -A --account-jwt-server-url http://127.0.0.1:9090/jwt/v1/
nsc push -A --account-jwt-server-url http://external-nats-account-server:9090/jwt/v1/
```

### Additional contract requirements

- The `nsc push` command accepts an `--account-jwt-server-url` flag, with short alias `-u`, that sets the account JWT server URL used for the push. The flag is optional; when it is supplied, the given URL is used as the account JWT server for the push instead of the URL configured in the operator JWT.
