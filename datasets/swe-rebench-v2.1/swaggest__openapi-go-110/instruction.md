setupRequest doesn't work with jsonschema.Struct
**Describe the bug**
When a `jsonschema.Struct` is passed to `setupRequest` it doesn't work. For example, when used with `oc.AddReqStructure`. [HIDDEN]

**To Reproduce**
[Here](https://go.dev/play/p/ARwi9ydGLc5) is an example for `HasTaggedFields` returning an incorrect answer.

**Expected behavior**
`setupRequest` should work on `jsonschema.Struct` the same way `setupResponse` does.

**Additional context**
I'm trying to add an OpenAPI schema to an existing APIs. I don't want to rewrite all the input structs, but wanted to extend them to include the URL params. Unfortunately, this didn't work due the aforementioned issue.

### Additional contract requirements

- Request setup must accept a `jsonschema.Struct` supplied via `AddReqStructure` and produce a request-body JSON Schema that includes the schema fields declared by that value, consistent with response setup.
