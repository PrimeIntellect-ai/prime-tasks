Add a configuration option to treat x-extensible-enum as an enum
Zalando's string format `x-extensible-enum` could be generated as an enum if requested by users.

The default should be not to treat these strings as enums as it could cause clients to break as new enum values are added. But for server-side development, it may be nicer to generate these definitions as enums

### Additional contract requirements

The opt-in is available through the existing `--http-model-opts` argument with the value `X_EXTENSIBLE_ENUMS`. When enabled, the generated enum includes the values declared by `x-extensible-enum`. Without this opt-in, those definitions remain strings.
