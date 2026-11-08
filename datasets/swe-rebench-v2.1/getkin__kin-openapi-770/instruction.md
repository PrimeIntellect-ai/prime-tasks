Bug: Default values still count as properties even if setting them is disabled.
https://github.com/getkin/kin-openapi/blob/ecb06bc5c05b010b9c1322486ff74f2178f7927c/openapi3/schema.go#L1774-L1816

[HIDDEN]

This counts towards `lenValue` (line 1813) and can falsely pass validations like `minProperties` that way.

I will add a PR to fix this bug.

### Additional contract requirements

- When default values are disabled, a schema default for an absent property must not affect `minProperties` or `maxProperties` validation.
- When default values are enabled and applied to an absent property, that property counts toward `minProperties` and `maxProperties` validation.
