Registry tool: `registry config configurations create` creates configurations with an empty location
After running `registry config configurations create local` in a new environment and configuring my server address and project, I noticed that `registry get apis` returned this error:

```
$ registry get apis
Error: unsupported pattern apis
Usage:
  registry get PATTERN [flags]

Flags:
      --filter string   filter selected resources
  -h, --help            help for get
      --nested          include nested subresources in YAML output
  -o, --output string   output type (name|yaml|contents) (default "name")

Global Flags:
      --address string             the server and port of the Registry API (eg. localhost:8080)
  -c, --config string              name of a configuration profile or path to config file
      --registry.address string    the server and port of the Registry API (eg. localhost:8080)
      --registry.insecure          if specified, client connects via http (not https)
      --registry.location string   the API Registry location
      --registry.project string    the API Registry project
      --registry.token string      the token to use for authorization to the API Registry

----
Need more help?
https://github.com/apigee/registry/wiki
```

`registry config set location global` fixes this, but since we are always using this value for location, could we make that the default?

(`insecure` is also a tripping point, maybe we should automatically set that whenever the address is set to localhost... or could we suggest fixing this setting when calls fail?)
