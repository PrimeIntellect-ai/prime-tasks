References outside #/components/... fail to parse
As noted in [apisprout#1](https://github.com/danielgtaylor/apisprout/issues/1#issuecomment-408490874) it looks like some references can fail to parse. For example:

```json
{
  "$ref": "#/paths/~1v1~1servers/get/responses/200/content/application~1json/schema/properties/meta"
}
```

will fail to parse but is valid according to [the spec](https://github.com/OAI/OpenAPI-Specification/blob/master/versions/3.0.1.md#reference-object). Rather than referencing a predefined component it is reusing a piece of another response schema. Ideally the parser would handle these cases regardless of what the link starts with.
