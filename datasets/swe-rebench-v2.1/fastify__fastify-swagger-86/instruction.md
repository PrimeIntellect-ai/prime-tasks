Support `tags` and `externalDocs` in dynamic mode
As per OpenAPI 2.0 specification, you are missing 2 top-level fields described here https://github.com/OAI/OpenAPI-Specification/blob/master/versions/2.0.md#fixed-fields:
- `tags`
- `externalDocs`

[HIDDEN]

I'm filing this issue because I found that `tags` was missing, but there may be more fields that are lacking deeper down, I didn't check.

### Additional contract requirements

- In dynamic mode, preserve a supplied `tags` value as a top-level field in the generated Swagger output.
- In dynamic mode, preserve a supplied `externalDocs` value as a top-level field in the generated Swagger output.
