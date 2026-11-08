Allow variable indexing in templates
Such as `my_variables[0]` (equivalent to my_variables.0) or `my_variables["hello"]`  (equivalent to my_variables.hello). The advantage being the indexed version can contain fields that are not valid Tera identifiers, such as `posts/tutorials` for example.

Potential issues (some might be non-existent after trying it):

- chained indexing: `myvar["hey"][0]`
- variable in indexes: `my_var[config.home]`. Could be not allowed and recommend to use `my_var | get(key=config.home)` instead

That might be a breaking change and should only be done once Pest reaches 1.0

### Additional contract requirements

- When parsing `{{ hey %}`, the error message must contain this exact substring: expected an integer, a float, a string, `true` or `false`, an identifier (must start with a-z), a dotted identifier (identifiers separated by `.`), a square bracketed identifier (identifiers separated by `.` or `[]`s), or an expression.
- When parsing `{% filter %}sd{% endfilter %}`, the error message must contain `expected an identifier (must start with a-z) or a function call`. When parsing `{% set = 1 %}`, `{% import "hello" as %}`, or `{% block %}`, the error message must contain `expected an identifier (must start with a-z)`.
