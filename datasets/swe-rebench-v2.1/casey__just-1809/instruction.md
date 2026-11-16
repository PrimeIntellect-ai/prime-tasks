completions and modules don't work together
The completions script uses `just --summary` to fetch a list of recipes. A recipe `bar` inside module `foo` is listed as `foo::bar`, however module recipes can't be invoked like this ("Justfile does not contain recipe `foo::bar`").

I'm not sure the best solution although I do personally find `foo::bar` easier syntax to read as `foo bar` in my mind looks like a recipe `foo` that takes a parameter `bar`.

I wonder whether `foo::bar` should be added as additional valid syntax to run a module's recipe?

### Additional contract requirements

- A recipe in a module must be invokable using its `::`-qualified path as an additional valid invocation syntax. For example, a recipe `bar` in module `foo` can be invoked as `foo::bar`; nested module recipes can be invoked using the full path, such as `foo::bar::baz`.
- For malformed path arguments, stderr must be exactly `error: Justfile does not contain recipe \`:foo::foo\`.\n`, `error: Justfile does not contain recipe \`foo::foo:\`.\n`, or `error: Justfile does not contain recipe \`foo:::foo\`.\n`, respectively. If the arguments are `:foo::foo` and `bar`, stderr must be exactly `error: Justfile does not contain recipes \`:foo::foo\` or \`bar\`.\n`.
