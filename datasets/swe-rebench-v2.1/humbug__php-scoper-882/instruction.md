Mark scoped symbols as private
IDEs support to not complete private classes when they come from third-party dependencies.

### Additional contract requirements

- Scoped declarations (classes, interfaces, traits, enums, functions and constants) are annotated with the PHPDoc tag `@internal`, so that IDEs can avoid suggesting them for auto-completion.
- The configuration option `tag-declarations-as-internal` (boolean, defaults to `true`) controls whether declarations are annotated with `@internal`.
- `Configuration::__construct(...)` accepts a trailing `bool $tagDeclarationsAsInternal` parameter.
- `Configuration::shouldTagDeclarationsAsInternal(): bool` returns the value of the `tagDeclarationsAsInternal` flag passed to the constructor.
- `TraverserFactory::__construct(...)` accepts a trailing `bool $tagDeclarationsAsInternal` parameter.
