Default string format setting for ZodDate
Thanks for creating a nice library😄

When converting a ZodDate to an openapi schema, the type is a string, and the format is unset and fixed.
However, regarding format, if there is one format that works best for one project, it would be somewhat redundant to set the format with the openapi function every time.

So what do you think about allowing pre-set default values for this format?
If this is a good suggestion, I would like to figure out how to modify it.

### Additional contract requirements

`createDocument` accepts an optional second options argument with a `defaultDateSchema` object. For every ZodDate converted while generating that document, the configured `format` is used without requiring the format to be set on each Zod schema. If no default format is configured, ZodDate continues to produce a string schema with no format.
