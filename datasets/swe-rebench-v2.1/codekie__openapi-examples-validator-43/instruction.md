Support for nullable
My schema has properties that can be nullable. However, when I pass in, for example `userId: null` I get a validation error saying it should be integer.

### Additional contract requirements

For an OpenAPI property declared `nullable: true`, a `null` example value is valid. Non-null example values must still satisfy the property's declared type. A `null` example remains invalid when its property is not declared nullable.
