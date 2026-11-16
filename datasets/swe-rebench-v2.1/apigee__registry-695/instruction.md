Registry tool: Use global flags for config create
If a user specifies any of flags that set a stored value during `config create`, the created config should save them. Eg.

      --registry.address string    the server and port of the registry api (eg. localhost:8080)
      --registry.insecure          if specified, client connects via http (not https)
      --registry.location string   the registry location
      --registry.project string    the registry project
