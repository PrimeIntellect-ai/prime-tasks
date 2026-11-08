`CompilerPanic` when using `len` and `empty` together
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.d76c6ed2
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

The compiler panic when using the builtin `len` on some `Bytes`, `String` or `DynArray` which is written as `empty(...)`.
``` Vyper
@external
def boo():
    e:uint256 = len(empty(DynArray[uint256,50]))
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 414, in parse_body
    ir = parse_stmt(stmt, context)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 388, in parse_stmt
    return Stmt(stmt, context).ir_node
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 40, in __init__
    self.ir_node = fn()
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 67, in parse_AnnAssign
    rhs = Expr(self.stmt.value, self.context).ir_node
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/expr.py", line 77, in __init__
    self.ir_node = fn()
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/expr.py", line 632, in parse_Call
    return DISPATCH_TABLE[function_name].build_IR(self.expr, self.context)
  File "/Users/trocher/Documents/thesis/vyper/vyper/builtins/functions.py", line 482, in build_IR
    return get_bytearray_length(arg)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/core.py", line 309, in get_bytearray_length
    return IRnode.from_list(LOAD(arg), typ=typ)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/core.py", line 580, in LOAD
    raise CompilerPanic("cannot dereference non-pointer type")
vyper.exceptions.CompilerPanic: cannot dereference non-pointer type

This is an unhandled internal compiler error. Please create an issue on Github to notify the developers.
https://github.com/vyperlang/vyper/issues/new?template=bug.md
```
### How can it be fixed?

[HIDDEN]

### Additional contract requirements

- Applying the built-in `len` to `empty(...)` values of type `Bytes`, `String`, or `DynArray` must compile without an internal compiler panic and evaluate to zero.
