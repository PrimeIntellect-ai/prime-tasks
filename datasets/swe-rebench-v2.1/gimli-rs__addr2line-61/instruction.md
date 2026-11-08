addr2line should use .symtab information
In the absence of `.debug_line` information, there is still other file and address information in `.debug_info` that we can use to give vague information about the address.

### Additional contract requirements

When `with_symbol_table` is enabled, an address that has no DWARF debug information but is covered by an entry in the object file's symbol table must resolve to a location (`Ok(Some(...))`) instead of `Ok(None)`. When `with_functions` is also enabled, the resolved location's function name is the symbol's name.
