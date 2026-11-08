Support custom mappings between schema formats and Swift types
Edit: differs from the original to a single global override instead of individual properties and I forgot parameter types. I think that we can start with a global override and somebody can request this fine tuning later.

---

Introduce a config option to override the Swift type when they are parsed and written:

```yaml
# schema
Pet:
  properties:
    id:
      type: string
    tag:
      type: string
      format: uuid

# config
swiftTypeOverrides:
  UUID: String # any occurrences of UUID are replaced with String, so `Pet.tag: String`
```

Config name open for improvement. Obviously, a developer might override to a type that cannot be decoded from/encoded to the original type, like `UUID: Int` or a type that does not exist, like `UUID: qwerty`. So, it is a developer responsibility to make sure that overriding types can be properly decoded/encoded and that they are a proper Swift type.

---

This can be further enhanced with imports as we should be trivially able to set an imported type after https://github.com/CreateAPI/CreateAPI/issues/85 is figured out. Using NaiveDate as an example removing the `useNaiveDate` option, we include the package as an import in the config and then set the type override:

```yaml
# schema
Pet:
  properties:
    birth_date:
      type: string
      format: date

# config
swiftTypeOverrides:
  Date: NaiveDate # any occurrences of Date are replaced with NaiveDate
```

Obviously, imported objects should be expected to properly decode/encode but that's an implementation detail of the imported type.

### Additional contract requirements

- Name the configuration option `dataTypes`. Configure integer format mappings under `dataTypes.integer`; for example:

```yaml
dataTypes:
  integer:
    int32: Int32
    int64: Int64
```

With this configuration, schema formats `int32` and `int64` generate Swift types `Int32` and `Int64`, respectively.

- Configure string format mappings under `dataTypes.string`; for example:

```yaml
dataTypes:
  string:
    uuid: String
```

With this configuration, schema format `uuid` generates the Swift type `String`.
