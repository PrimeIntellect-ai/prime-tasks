`identityProviders` with `--dry-run` mode produces incorrect ClusterConfig
This can be reproduced by using the example ClusterConfig in `examples/27-oidc-provider.yaml`.

```shell
$ eksctl create cluster -f examples/27-oidc-provider.yaml --dry-run | eksctl create cluster -f -
Error: loading config file "-": error unmarshaling JSON: while decoding JSON: couldn't unmarshal to IdentityProvider, invalid type
```
