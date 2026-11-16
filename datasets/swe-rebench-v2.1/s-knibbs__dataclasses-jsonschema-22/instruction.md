Include enum name information in the JSON schema
To improve the generation of code from the JSON schema, an extension field ('x-enum-name') could be added to any fields using an enum.

### Additional contract requirements

Generated JSON schemas include an `x-enum-name` extension identifying the enum type on each enum-typed field.
