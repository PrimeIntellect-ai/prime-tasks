struct-tag: support "properties" tag
"properties" was added to the [well-known struct tags on Go wiki](https://go.dev/wiki/Well-known-struct-tags#list-of-well-known-struct-tags)

- https://github.com/golang/go/issues/72759

- https://github.com/golang/wiki/pull/44

It could be added to revive to the very sane way TOML support was added recently to [struct-tag](https://github.com/mgechev/revive/blob/master/RULES_DESCRIPTIONS.md#struct-tag) rule

- https://github.com/mgechev/revive/pull/1255

Here is the documentation of the format of this tag

https://pkg.go.dev/github.com/magiconair/properties#Properties.Decode

Based on my understanding of the code and documentation only the following options are supported
- "-" ignored
- "default" (without it a field is required)
   Note: There is a special notation using `;` for slice/array default value.
- "layout" (only for time.Time type)

cc @magiconair (properties lib owner)

### Additional contract requirements

The `struct-tag` rule supports the `properties` struct tag. The tag name is the part before the first comma and the options follow after commas. The supported options are:

- `-`: the field is ignored.
- `default`: gives the field a default value; without it the field is required. For slice and array fields the default value may list several elements separated by `;`.
- `layout`: only applicable to fields of type `time.Time`.

A `properties` tag is reported as invalid, with the following message, when:

- a `default` value does not match the field's type: `field type and default value type mismatch in properties tag`;
- more than one `default` option is present: `properties tag accepts only one default option`;
- a `layout` option has no value or a value that is empty after trimming spaces: `malformed layout option for properties tag`;
- a `layout` option is used on a field whose type is not `time.Time`: `layout option is only applicable to fields of type time.Time in properties tag`;
- an option is not one of the supported options: `unknown option "<option>" in properties tag`, where `<option>` is the option text as written in the tag.
