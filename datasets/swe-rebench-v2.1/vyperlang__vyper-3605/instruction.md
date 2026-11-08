Document/define storage slots for reentrancy locks
We should define somewhere properly how the storage slots for reentrancy locks are chosen. In the compiler code, we can see this [here](https://github.com/vyperlang/vyper/blob/master/vyper/semantics/analysis/data_positions.py#L98). Also, I feel we should disallow empty reentrancy locks like `@nonreentrant("")` or `@nonreentrant(" ")` for safety reasons.

### Additional contract requirements

- `validate_identifier(attr, ast_node=None)` is a public function in `vyper/ast/identifiers.py`.
- A valid identifier matches `^[_a-zA-Z][a-zA-Z0-9_]*$` and is not a reserved keyword (compared case-insensitively against `RESERVED_KEYWORDS`). Anything else, including the empty string and whitespace-only strings, is invalid.
- `validate_identifier` returns `None` for a valid identifier and raises `StructureException` for an invalid one.
- When an `ast_node` is passed, the raised `StructureException` includes that node so the error message carries source-location information.
- In a compiler-generated storage layout without overrides, each distinct reentrancy-lock key gets its own storage slot, starting at slot 0 in the order its key first appears among functions. Later functions using the same key reuse that slot. These lock slots are allocated before ordinary storage variables.
