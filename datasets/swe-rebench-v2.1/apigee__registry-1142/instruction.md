Registry tool: Let's drop the `APG_` prefix from environment variables.
This vestigal configuration came from the automatically-generated CLI, which we've since replaced with `registry config` subcommands. As discussed in #1107, if we remove the `APG_` prefix, then we can use `REGISTRY_ADDRESS`, etc. to configure the `registry` and related tools in containers (and anywhere).
