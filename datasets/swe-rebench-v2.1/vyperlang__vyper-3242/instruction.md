`AttributeError` when using invalid expression as loop's iterator
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.4ae2527f
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

Trying to use something else than a `Name` as the iterator of a `For` loop leads the compiler to output an `AttributeError`.
Bug similar to #3239 but as an `id` field is expected in the iterator's node and `Name` is the only kind of node with such field, it shouldn't be possible to compile invalid code, the issue is only about the unclear displayed error I think.

```Vyper
@external
def foo():
    for a[1] in [1,2]:
        pass
```
```Bash
Error compiling: tests/customs/code.vy
Traceback (most recent call last):
  File "/Users/trocher/Documents/thesis/vyper/venv/bin/vyper", line 11, in <module>
    load_entry_point('vyper==0.3.8', 'console_scripts', 'vyper')()
  File "/Users/trocher/Documents/thesis/vyper/vyper/cli/vyper_compile.py", line 57, in _parse_cli_args
    return _parse_args(sys.argv[1:])
  File "/Users/trocher/Documents/thesis/vyper/vyper/cli/vyper_compile.py", line 154, in _parse_args
    compiled = compile_files(
  File "/Users/trocher/Documents/thesis/vyper/vyper/cli/vyper_compile.py", line 294, in compile_files
    compiler_data = vyper.compile_codes(
  File "/Users/trocher/Documents/thesis/vyper/vyper/evm/opcodes.py", line 226, in _wrapper
    return fn(*args, **kwargs)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/__init__.py", line 141, in compile_codes
    exc_handler(contract_name, exc)
  File "/Users/trocher/Documents/thesis/vyper/vyper/cli/vyper_compile.py", line 189, in exc_handler
    raise exception
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/__init__.py", line 138, in compile_codes
    out[contract_name][output_format] = OUTPUT_FORMATS[output_format](compiler_data)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/output.py", line 248, in build_bytecode_output
    return f"0x{compiler_data.bytecode.hex()}"
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/functools.py", line 966, in __get__
    val = self.func(instance)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 150, in bytecode
    self.assembly, is_runtime=False, no_bytecode_metadata=self.no_bytecode_metadata
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/functools.py", line 966, in __get__
    val = self.func(instance)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 141, in assembly
    return generate_assembly(self.ir_nodes, self.no_optimize)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 126, in ir_nodes
    ir, ir_runtime, sigs = self._ir_output
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/functools.py", line 966, in __get__
    val = self.func(instance)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 122, in _ir_output
    return generate_ir_nodes(self.global_ctx, self.no_optimize)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 117, in global_ctx
    return GlobalContext(self.vyper_module_folded)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 107, in vyper_module_folded
    module, storage_layout = self._folded_module
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/functools.py", line 966, in __get__
    val = self.func(instance)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 101, in _folded_module
    return generate_folded_ast(
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 229, in generate_folded_ast
    validate_semantics(vyper_module_folded, interface_codes)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/__init__.py", line 13, in validate_semantics
    validate_functions(vyper_ast)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/local.py", line 59, in validate_functions
    FunctionNodeVisitor(vy_module, node, namespace)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/local.py", line 179, in __init__
    self.visit(node)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/local.py", line 222, in visit
    super().visit(node)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/common.py", line 20, in visit
    visitor_fn(node, *args)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/local.py", line 438, in visit_For
    [HIDDEN]
AttributeError: 'Subscript' object has no attribute 'id'
```

### Additional contract requirements

- A `for` loop with a non-`Name` iterator target, such as `a[1]`, must be rejected during compilation with `vyper.exceptions.StructureException`, rather than an `AttributeError`.
