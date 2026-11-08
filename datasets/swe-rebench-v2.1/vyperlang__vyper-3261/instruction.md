`TypeCheckFailure` when accessing the members of a literal or constant `address`
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.02339dfd
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

Accessing the members of a literal or constant `address` leads the compiler to fail type checking.

```Vyper
a:constant(address) = 0x0000000000000000000000000000000000000000

@external
def foo():
    x:uint256 = a.balance
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 258, in generate_ir_nodes
    ir_nodes, ir_runtime, function_sigs = module.generate_ir_for_module(global_ctx)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/module.py", line 163, in generate_ir_for_module
    runtime, internal_functions = _runtime_ir(runtime_functions, all_sigs, global_ctx)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/module.py", line 104, in _runtime_ir
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/expr.py", line 211, in parse_Attribute
    addr = Expr.parse_value_expr(self.expr.value, self.context)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/expr.py", line 704, in parse_value_expr
    return unwrap_location(cls(expr, context).ir_node)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/expr.py", line 79, in __init__
    raise TypeCheckFailure(f"{type(node).__name__} node did not produce IR. {self.expr}")
vyper.exceptions.TypeCheckFailure: Hex node did not produce IR. vyper.ast.nodes.Hex:
     4 def foo():
---> 5     x:uint256 = a.balance
-----------------------^

This is an unhandled internal compiler error. Please create an issue on Github to notify the developers.
https://github.com/vyperlang/vyper/issues/new?template=bug.md
```

### Additional contract requirements

- The `.balance` attribute is available on any value of type `address`, whether it is a literal address, a `constant(address)`, or a variable of type `address`. It evaluates to the current balance of that address in wei as a `uint256`, and evaluates to `0` when the address has no balance.
