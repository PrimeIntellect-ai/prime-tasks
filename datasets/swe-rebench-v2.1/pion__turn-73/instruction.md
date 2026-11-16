Add support for customizing SOFTWARE attribute value
Currently this is hard-coded and should be specifiable either through configuration or environment variables.

### Additional contract requirements

- The SOFTWARE attribute value must no longer be hard-coded. It is taken from configuration at the command level: the `simple-turn` server command reads it from the `SOFTWARE` environment variable, and the `client` command accepts it through a `-software` command-line flag.
- When a value is configured for the server, every binding response it sends carries a SOFTWARE attribute with exactly that value.
- When a value is configured for the client, every binding request it sends carries a SOFTWARE attribute with exactly that value.
