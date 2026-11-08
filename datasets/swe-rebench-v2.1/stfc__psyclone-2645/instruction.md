Extend SymbolTable.lookup() with a "default value" argument to avoid need for try...except.
Currently the `lookup` method of SymbolTable will raise a `KeyError` if a Symbol cannot be found (c.f. a Python dict). However, this leads to a lot of try..except blocks which could be avoided if we could just tell the method to return e.g. `None` if no Symbol is found. By adding an optional argument we can make this change backwards-compatible (which is good because it would otherwise touch a lot of code).

### Additional contract requirements

- `SymbolTable.lookup()` accepts an optional fallback argument named `otherwise`. If no symbol is found, it returns the supplied value; if `otherwise` is omitted, it raises `KeyError`.
