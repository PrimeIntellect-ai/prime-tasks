Python client does not resolve relative paths in kubeconfig
When using relative paths in `~/.kube/config` like this:
```yaml
- cluster:
    certificate-authority: certs/cfm.ca.crt
```

The following [error message](https://gist.github.com/webwurst/5b3aece21c45a634eb0db6e14b2aa3c5#file-z-error-txt) is thrown:
```
kubernetes.client.rest.ApiException: (0)
Reason: SSLError
[Errno 2] No such file or directory
```

Additionally it would be nice when in case of a `No such file or directory` error, the tried path would be shown. 😃

### Additional contract requirements

- `load_kube_config(config_file, context=None)` (the client's entry point for
  loading a kube-config file) must resolve relative file references inside that
  file against the directory containing `config_file`, without the caller
  supplying any base path. This is the `~/.kube/config` use case.
- When a referenced file does not exist, the raised `ConfigException` message
  must include the path that was tried.
