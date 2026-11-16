Cache contents of config file
Placing a console.log inside config.js shows that we're loading the config from scratch once per rule. We should be loading the config once per invocation of sass-lint.

I'm referring to using sass-lint from the CLI, and specifying a config file. e.g. `sass-lint -c .sass-lint.yml`

### Additional contract requirements

- The module `lib/config.js` exports a function `config(options, configPath)` that returns the resolved configuration object, formed by recursively merging the default configuration, any discovered user configuration file, and the supplied inline options.
- The configuration option `merge-default-rules` (boolean, defaults to `true`) controls whether the default rules are merged into the resolved configuration.
- The configuration option `cache-config` (boolean, defaults to `false`) controls whether the resolved configuration is cached. When `cache-config` is `true`, the resolved configuration is cached and the cached configuration is returned on subsequent calls; when it is `false`, the configuration is resolved from scratch on every call.
- When the CLI is invoked with a specified config file (`-c, --config`) and `cache-config` is `true`, that config file is loaded only once during the invocation.
