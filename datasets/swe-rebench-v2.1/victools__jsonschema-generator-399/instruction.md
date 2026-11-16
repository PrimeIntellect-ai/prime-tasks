Support the "format" string tag without the other OpenAPI format-values
When looking into how to get the `"format"` tag properly formatted following the specs https://json-schema.org/understanding-json-schema/reference/string#format, I found that the only supported option for that is the `Option.EXTRA_OPEN_API_FORMAT_VALUES`. Nevertheless, this introduces`"format"` tags also for properties of numeric types that are not defined in the json-schema specs.

I know that there is a way to implement this with a customized method,  but it would be nice to have support with an `Option` to use the supported built-in formats (https://json-schema.org/understanding-json-schema/reference/string#built-in-formats)  from the json-schema specs (without relying on third-party OpenAPI custom formats).

Is there a possibility to support that feature out-of-the-box with either an option or directly when a version schema supports that built-in format?

*Reproduction*: I realized when I tried to use the `2019-09` schema with a model containing an `UUID` and an `Integer`, expecting to either get a `"format": uuid` with some option (i.e., `Option.ADDITIONAL_FIXED_TYPES`) but the only way was providing the OpenAPI format values that are also adding the `"format": int32` to the `number` and `integer` fields.

### Additional contract requirements

- Add a public enum constant `Option.STANDARD_FORMATS` in `com.github.victools.jsonschema.generator.Option`.
- Add a public method `boolean shouldIncludeStandardFormatValues()` to the `com.github.victools.jsonschema.generator.SchemaGeneratorConfig` interface. It returns `true` if and only if the `Option.STANDARD_FORMATS` option is enabled for the configuration, and `false` otherwise.
- When `Option.STANDARD_FORMATS` is enabled together with `Option.ADDITIONAL_FIXED_TYPES`, the built-in JSON Schema `"format"` values are emitted for the corresponding simple types: `"date"` for `java.time.LocalDate`; `"date-time"` for `java.time.LocalDateTime`, `java.time.ZonedDateTime`, `java.time.OffsetDateTime`, `java.time.Instant`, `java.util.Date` and `java.util.Calendar`; `"time"` for `java.time.LocalTime` and `java.time.OffsetTime`; `"duration"` for `java.time.Duration` and `java.time.Period`; `"uuid"` for `java.util.UUID`; and `"uri"` for `java.net.URI`.
- Enabling `Option.STANDARD_FORMATS` without `Option.EXTRA_OPEN_API_FORMAT_VALUES` does not add OpenAPI numeric formats such as `int32` to numeric types.
