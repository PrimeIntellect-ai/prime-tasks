`add_resolve_functions_to_schema` should support Scalars parse_value and parse_literal
Currently Ariadne Scalar support is limited to serializing python types to JSON before returning them to client, but we also want to support using custom scalars for input.

Our `add_resolve_functions_to_scalar` utility could support following use-cases:

Code below results in one-way only scalar:

- `type_defs = {'Scalar': {'serialize': callable}}`

And this code results in two-way scalar:

- `type_defs = {'Scalar': {'serialize': callable, 'parse_value': callable, 'parse_literal': callable}}` - explicit syntax for two-directional scalar.
