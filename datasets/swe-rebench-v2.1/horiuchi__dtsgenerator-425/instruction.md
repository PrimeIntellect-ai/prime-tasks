Config file could not be loaded
Hello,

I just tried to update to dtsgen 3.0.1. Sadly I always get an error when trying to generate dtos: `Error to load config file from dtsgen.json`.

A few things to note:
* I wouldn't need a configuration file for what I want to do, it is surprising `dtsgen` is still looking for it.
* I tried to create a stub file, because I do not need any plugins, but it seems it cannot even find that file. Maybe it tries to load it from `node_modules/dtsgenerator/bin`?

When I come home I will try to investigate further.

Thanks,
Christian

### Additional contract requirements

- Running `dtsgen` without supplying a configuration file must not fail or report an error merely because a default configuration file (such as `dtsgen.json`) is absent. In particular, when the `-c`/`--config` option is omitted, no message of the form `Error to load config file from <path>` may be printed.
- `initialize(argv: string[])` in `src/commandOptions` parses the supplied argument vector and returns the commander command.
- The parsed values are stored on the exported mutable `opts` object (the default export of `src/commandOptions`), whose `configFile` property is `undefined` when the `-c`/`--config` option is omitted and equals the value supplied with `-c`/`--config` when the option is given.


- `initialize(argv: string[])` parses the supplied argument vector and returns the Commander command for the caller to use.
- When `-c`/`--config` is omitted, the exported mutable `opts.configFile` value is `undefined`. When the option is supplied, `opts.configFile` equals the supplied path.
