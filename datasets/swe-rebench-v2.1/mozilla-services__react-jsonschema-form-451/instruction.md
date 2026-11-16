Option to turn off enum fields defaulting to first item
### Prerequisites

- [x] I have read the [documentation](https://github.com/mozilla-services/react-jsonschema-form/blob/master/README.md#readme);
- [ ] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.

### Description

We have string fields that use enums and are required fields. On the form, we'd like to not have them automatically default to the first item in the enum, so that the required validation is triggered if a user skips the field. Ideally we could use the `default` property in the schema for that, but in our case the default should really be `undefined`. So it would be good to have the ability to skip the enum specific default behavior and use the normal string field behavior.

This could be a Form component prop or an option in the uiSchema for a field, I think. I don't see a way to do it in the normal schema. At the form level would work for me.

I can submit a PR for this if you're open to it.

### Additional contract requirements

- Enum fields must no longer default to the first enum value. When a field schema declares an `enum` and specifies no `default`, the field value is `undefined`. This removal of the enum defaulting applies to every enum field without any additional configuration.
- A single-select field whose value is `undefined` renders its `<select>` with the empty value `""`.
- When a `placeholder` is supplied for a field (for example via `ui:options.placeholder` in the uiSchema) and the schema has no `default`, the select widget renders an extra empty `<option value="">` as the first option whose text is the placeholder string.
- Selecting the empty option sets the field value to `undefined` for a single select (and to `[]` for a multiple select).
- Boolean enum options are rendered with the option values `"true"` and `"false"`.
- For a single-select enum field whose schema has no default, render an empty `<option value="">` as the first option even when no placeholder is supplied.
