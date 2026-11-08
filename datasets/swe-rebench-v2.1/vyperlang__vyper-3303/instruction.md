The usage of `empty` is not prevented for mappings
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.7ff8f307
* OS: OSX
* Python Version (output of `python --version`): 3.7.0

### What's your issue about?

Trying to use `empty` on a mapping type leads to a `TypeCheckFailure`.

```Vyper
@external
def test():
    a:uint256 = empty(HashMap[uint256, uint256])[0]
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/output.py", line 82, in build_ir_output
    return compiler_data.ir_nodes
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 126, in ir_nodes
    ir, ir_runtime, sigs = self._ir_output
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/functools.py", line 966, in __get__
    val = self.func(instance)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 122, in _ir_output
    return generate_ir_nodes(self.global_ctx, self.no_optimize)
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 258, in generate_ir_nodes
    ir_nodes, ir_runtime, function_sigs = module.generate_ir_for_module(global_ctx)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/module.py", line 162, in generate_ir_for_module
    runtime, internal_functions = _runtime_ir(runtime_functions, all_sigs, global_ctx)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/module.py", line 103, in _runtime_ir
    func_ir = generate_ir_for_function(func_ast, all_sigs, global_ctx, skip_nonpayable_check)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/function_definitions/common.py", line 62, in generate_ir_for_function
    o = generate_ir_for_external_function(code, sig, context, skip_nonpayable_check)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/function_definitions/external_function.py", line 199, in generate_ir_for_external_function
    body += [parse_body(code.body, context, ensure_terminated=True)]
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 413, in parse_body
    ir = parse_stmt(stmt, context)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 387, in parse_stmt
    return Stmt(stmt, context).ir_node
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 40, in __init__
    self.ir_node = fn()
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 67, in parse_AnnAssign
    rhs = Expr(self.stmt.value, self.context).ir_node
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/expr.py", line 77, in __init__
    self.ir_node = fn()
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/expr.py", line 353, in parse_Subscript
    ir_node = get_element_ptr(sub, index)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/core.py", line 570, in get_element_ptr
    ret = _get_element_ptr_mapping(parent, key)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/core.py", line 554, in _get_element_ptr_mapping
    raise TypeCheckFailure(f"bad dereference on mapping {parent}[{key}]")
vyper.exceptions.TypeCheckFailure: bad dereference on mapping ~empty <empty(HashMap[uint256, uint256])>[0 <0>]

This is an unhandled internal compiler error. Please create an issue on Github to notify the developers.
https://github.com/vyperlang/vyper/issues/new?template=bug.md
```

### How can it be fixed?

`empty` should probably not be allowed for mappings types.

### Additional contract requirements

- Using `empty` on a mapping type (for example `empty(HashMap[uint256, uint256])`) must fail compilation with a `TypeMismatch` error.
- The `TypeMismatch` error raised when `empty` is used on a mapping type must include the text `Cannot use empty on HashMap`.
