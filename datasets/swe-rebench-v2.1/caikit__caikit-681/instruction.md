Support multiple remote servers in `RemoteModelFinder`
## Is your feature request related to a problem? Please describe.

The `RemoteModelFinder` allows a single `caikit.runtime` to proxy requests to a single remote `caikit.runtime` server for the collection of models loaded there. This feature request is to extend that functionality to support multiple remote servers behind a single instance of `RemoteModelFinder`.

## Describe the solution you'd like

* Allow the `connection.hostname` key in the config to include a template that can be filled in with the `model_name`/`model_id`
    * This allows the set of connections to change dynamically without rolling over the server to reload config
* Add support for a `remote_connections` config to pre-populate connections to multiple known servers.

## Describe alternatives you've considered

The desired feature can be accomplished with the current implementation by having one configured `RemoteModelFinder` for each remote server, however this set of servers would be immutable after boot, so the server acting as the proxy would need to be rolled over to update the mapping.

### Additional contract requirements

- `remote_connections` is a list of connection configurations; each entry supplies connection settings for a remote server, allowing one finder to discover models from multiple configured servers. A discovered model is associated with the server that reported it.
- A `connection.hostname` template must support the positional `{}` placeholder; for example, `foo.{}.svc` resolves to `foo.<model_name>.svc`.
