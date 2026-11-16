`pop` and `append` are not reserved keywords
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.ae7d6d28
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

`pop` and `append` are not Vyper reserved keywords. While the usage of `pop` happen to be restricted as it is a reserved keyword for the EVM `POP` instruction, the usage of `append` is not restricted and the compiler will try to interpret it as the dynamic array's homonymous method.

For example, trying to compile the following contract will fail with an `AssertionError`.
```Vyper
interface Foo:
    def append(a:uint256): payable

@external
def bar(x: address):
    a: Foo = Foo(x)
    a.append(1)
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/module.py", line 165, in generate_ir_for_module
    runtime, internal_functions = _runtime_ir(runtime_functions, all_sigs, global_ctx)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/module.py", line 103, in _runtime_ir
    func_ir = generate_ir_for_function(func_ast, all_sigs, global_ctx, skip_nonpayable_check)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/function_definitions/common.py", line 62, in generate_ir_for_function
    o = generate_ir_for_external_function(code, sig, context, skip_nonpayable_check)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/function_definitions/external_function.py", line 182, in generate_ir_for_external_function
    body += [parse_body(code.body, context, ensure_terminated=True)]
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 410, in parse_body
    ir = parse_stmt(stmt, context)
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 384, in parse_stmt
    return Stmt(stmt, context).ir_node
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 40, in __init__
    self.ir_node = fn()
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 50, in parse_Expr
    return Stmt(self.stmt.value, self.context).ir_node
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 40, in __init__
    self.ir_node = fn()
  File "/Users/trocher/Documents/thesis/vyper/vyper/codegen/stmt.py", line 133, in parse_Call
    assert isinstance(darray.typ, DArrayT)
AssertionError
```
### How can it be fixed?

Adding them as reserved keyword should be enough.

### Additional contract requirements

- The example contract above must compile successfully.
- An external interface may declare a method named `append` that takes a single `uint256` argument, is marked `payable`, and returns no value; calling it on an instance of the interface must compile.
- An external interface may declare a method named `pop` that takes no arguments, is marked `payable`, and returns no value; calling it on an instance of the interface must compile.

- Calls to dynamic arrays’ existing `append` and `pop` member functions must retain their existing behavior.
