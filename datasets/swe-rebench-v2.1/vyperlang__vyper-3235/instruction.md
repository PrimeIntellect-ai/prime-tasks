Folding constants can replace `Enum`'s fields
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.4ae2527f
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

When folding replace user defined constants, it also replace members of `Enum` that happen to be named after a constant.

The following contract result in the joined `AttributeError`.

```Vyper
a:constant(uint256) = 1

enum A:
    a
```
```Bash
Error compiling: tests/customs/code.vy
Traceback (most recent call last):
  File "/Library/Frameworks/Python.framework/Versions/3.8/bin/vyper", line 8, in <module>
    sys.exit(_parse_cli_args())
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/__init__.py", line 12, in validate_semantics
    add_module_namespace(vyper_ast, interface_codes)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/module.py", line 43, in add_module_namespace
    ModuleAnalyzer(vy_module, interface_codes, namespace)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/module.py", line 77, in __init__
    self.visit(node)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/common.py", line 20, in visit
    visitor_fn(node, *args)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/module.py", line 250, in visit_EnumDef
    obj = EnumT.from_EnumDef(node)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/types/user.py", line 112, in from_EnumDef
    member_name = node.value.id
AttributeError: 'Int' object has no attribute 'id'
```

### How can it be fixed?

Fill this in if you know how to fix it.
