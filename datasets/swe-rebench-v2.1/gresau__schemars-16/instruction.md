Option<bool> gets required in schema
Hello, and **thank you for a great project!**

I suspect I've encountered a bug (or I'm holding it wrong), but for some reason optional bools are set as required in definitions.

The version I'm using is `0.7.0-alpha-1`

```
struct MyStruct {
  pub foo: Option<bool>
}

pub fn get_schema() -> String {
    let settings = schemars::gen::SchemaSettings::draft07().with(|s| {
        s.option_nullable = false;
        s.option_add_null_type = false;
    });
    let gen = settings.into_generator();
    let schema = gen.into_root_schema_for::<config::MyStruct>();
    serde_json::to_string_pretty(&schema).unwrap()
}
```

Generates the following schema:

```
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "MyStruct",
  "type": "object",
  "required": [
    "foo"
  ],
  "properties": {
    "foo": {
      "type": "boolean"
    }
  }
}
```

If I add `#[serde(default)]` to `foo` it removes the requirement.

Would it make sense to add an option to `SchemaSettings` that says "Don't make Options required". I realize that the logic for this probably is more complicated since we have to take `option_nullable` and `option_add_null_type` into account, but having some kind of sensible default for this would make adoption easier.

Again, thanks for your great work. Much appreciated!

### Additional contract requirements

For a derived struct, a field whose type is `Option<T>` is optional in the generated object schema by default, including when both `option_nullable` and `option_add_null_type` are disabled. The field remains present in `properties`, with the schema for its inner type when nullability is disabled.
