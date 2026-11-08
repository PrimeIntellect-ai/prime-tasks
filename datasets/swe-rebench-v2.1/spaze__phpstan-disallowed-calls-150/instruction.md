Add flag support for params
I'd like to allow params when a flag is present ia param value like `JSON_HEX_TAG | JSON_HEX_APOS`. Currently that's not possible and a param value is treated as scalar value.

This will need a new param format, one idea is mentioned in https://github.com/spaze/phpstan-disallowed-calls/pull/141#issuecomment-1327289245

After adding the support, `json_decode()` with `JSON_THROW_ON_ERROR` could be added to the "loose" config as originally proposed by @ilazaridis in #141.

Also this should be updated too then
https://github.com/spaze/phpstan-disallowed-calls/blob/332969d0aa67ddb8597c2f1248268d69ebf5f9c7/disallowed-loose-calls.neon#L9-L12

### Additional contract requirements

- Support the `allowParamFlagsInAllowed` configuration option for parameter conditions that selectively allow calls in allowed files. A call should match when the specified flag is present in the parameter value, including when combined with other flags.
