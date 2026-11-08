CLI options should override config file
Currently I think CLI options are overridden by the config file:

``` js
[HIDDEN]
```

AFAIK it's most common to be the other way round as it's often useful to be able to override a single config option on the CLI.

Should be a simple change and maybe a test to verify.

### Additional contract requirements

- When a CLI option and the config file both specify a value for the same option, the CLI value takes precedence. Options not specified on the CLI continue to use their config-file values.
