Handling of integer number types with `int16` format.
As a follow up to https://github.com/microsoft/OpenAPI.NET.OData/pull/593

The `integer` types were replaced in the openapi description with `number` types which presented the a inconsistency in the generation.  Due to the case at the line below.

https://github.com/microsoft/kiota/blob/a14fb8130851192316238393e4958844069967b8/src/Kiota.Builder/KiotaBuilder.cs#L1159C19-L1159C26

Properties with the type as `integer` and format as `int16` would be projected as type `integer` in the codeDom.

However changing the type to `integer` results in the type being projected as `double` as opposed to `integer` before as there is no case to handle the `integer` with `int16` format.

### Additional contract requirements

- An OpenAPI schema with type `number` and format `int16` must project to CodeDOM type `integer`; a schema with type `integer` and format `int16` must continue to project to `integer`.
