Support for named args in `handlebars_helper` macro?
It seems it's currently not possible to use the `handlebars_helper` macro for defining helpers with optional named args.
Could support be added by using `hash_get`? :)

The syntax for these args could be `arg: Option<Type>` or `arg=Option<Type>`.

### Additional contract requirements

`handlebars_helper!` supports optional named hash arguments declared after any positional arguments inside braces, using `name: type = default_literal` (for example, `{cur: str="$"}`). A helper can be called with that hash argument supplied in the template or without it; omission uses the declared default. This also applies when the helper has no positional arguments.
