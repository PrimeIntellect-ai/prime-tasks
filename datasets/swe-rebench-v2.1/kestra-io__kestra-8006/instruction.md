Some deprecation notice doesn't appear in the embedded doc
### Describe the issue

For the io.kestra.plugin.scripts.python.Script task, the deprecation notice icon appear for some properties but not for all, (I.E : OutputDirectory), while the validator do tag the flow with a warn since it use a deprecated property.

![Image](https://github.com/user-attachments/assets/b50dc565-6747-4c3e-aebd-57dd7497d1ec)

### Environment

- Kestra Version: 0.21.5

### Additional contract requirements

- `io.kestra.core.docs.JsonSchemaGenerator` exposes a public method `properties(Class<T> base, Class<? extends T> cls)` returning `Map<String, Object>`. It produces a JSON-Schema fragment describing the configurable properties of `cls`, merging the documentation and default values declared on the fields of `cls` with those of its base task class `base`.
- For a property whose field carries a `@Schema` annotation, the annotation's `title` and `description` are propagated into the generated property schema.
- For a property whose field is deprecated, the generated property schema marks it with `$deprecated` set to `true`.
- For a property whose field declares a default value, that default is propagated into the generated property schema. This holds for non-string properties (such as integer properties) as well as string properties.
