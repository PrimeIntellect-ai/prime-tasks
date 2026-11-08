[2.x] Implement system mounts interface
Implement the [`/sys/mounts`](https://www.vaultproject.io/api-docs/system/mounts) endpoints in the new 2.x branch. This will mostly be useful for the integration tests to not shell out, so can be considered optional.

### Additional contract requirements

Provide a public namespace `vault.sys.mounts` exposing the following functions:

- `list-mounts(client)` – performs `GET /sys/mounts` and returns a map whose keys are
  mount-point strings (for example `"cubbyhole/"`) and whose values are maps of the
  mount configuration with kebab-cased keys. It never returns nil; an exception is
  thrown on HTTP error.
- `enable-secrets!(client, path, params)` – performs `POST /sys/mounts/<path>` with a
  JSON body whose keys are snake-cased. `params` contains at least `:type` and may
  contain `:description`, `:config` and `:options`; every supplied key is included in
  the request body. It returns nil on success; an exception is thrown on HTTP error.
- `disable-secrets!(client, path)` – performs `DELETE /sys/mounts/<path>`. It returns
  nil on success; an exception is thrown on HTTP error.
- `read-secrets-configuration(client, path)` – performs `GET /sys/mounts/<path>` and
  returns the mount configuration with kebab-cased keys. It never returns nil; an
  exception is thrown on HTTP error.
- `read-mount-configuration(client, path)` – performs `GET /sys/mounts/<path>/tune`
  and returns the mount's tuned parameters (for example `:default-lease-ttl`,
  `:max-lease-ttl`, `:description`) with kebab-cased keys. It never returns nil; an
  exception is thrown on HTTP error.
- `tune-mount-configuration!(client, path, params)` – performs
  `POST /sys/mounts/<path>/tune` with a JSON body whose keys are snake-cased. It
  returns nil on success; an exception is thrown on HTTP error.
