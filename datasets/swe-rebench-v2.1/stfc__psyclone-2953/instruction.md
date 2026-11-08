symbol.resolve_type fails for transitive imports
```
    ~~~~~~~~~~~~~^^^^^^^^^^^^^^^
  File "/home/centos/workspace/psyclone/PSyclone/src/psyclone/transformations.py", line 597, in validate
    self.validate_it_can_run_on_gpu(node, options)
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^
  File "/home/centos/workspace/psyclone/PSyclone/src/psyclone/transformations.py", line 459, in validate_it_can_run_on_gpu
    symbol.resolve_type()
    ~~~~~~~~~~~~~~~~~~~^^
  File "/home/centos/workspace/psyclone/PSyclone/src/psyclone/psyir/symbols/symbol.py", line 263, in resolve_type
    if extern_symbol.initial_value:
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'Symbol' object has no attribute 'initial_value'
```

### Additional contract requirements

If an imported symbol resolves externally to a bare `Symbol` with no type,
`resolve_type` must raise `SymbolError` to report that its type cannot be
resolved. It must not fail with an `AttributeError` while handling the
untyped external symbol.
