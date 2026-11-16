`HashMap` no longer accepts `Enum` as key type
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.02339dfd
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

`Enum` are no longer accepted as key type of `HashMap` but were in v0.3.7.

```Vyper
enum A:
    a
foo:HashMap[A,uint256]
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/analysis/module.py", line 194, in visit_VariableDecl
    type_ = type_from_annotation(node.annotation)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/types/utils.py", line 99, in type_from_annotation
    return type_ctor.from_annotation(node)
  File "/Users/trocher/Documents/thesis/vyper/vyper/semantics/types/subscriptable.py", line 81, in from_annotation
    raise InvalidType("can only use primitive types as HashMap key!", k_ast)
vyper.exceptions.InvalidType: can only use primitive types as HashMap key!
  contract "tests/customs/code.vy:4", line 4:12
       3     a
  ---> 4 foo:HashMap[A,uint256]
  -------------------^
       5
```

### How can it be fixed?

[HIDDEN]
