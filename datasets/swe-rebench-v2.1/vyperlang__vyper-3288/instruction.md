Incorrect `TypeMismatch` for `_MIN_MAX` with certain signed types
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.d76c6ed2
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

When `min` or `max` is given two values `a,b` of type `intX` where `X>128`, if `a` or `b` is negative and the other one is greater than or equal to `2 ** 127`, the compiler outputs a `TypeMismatch` although they have the same type. [HIDDEN]

For example, compiling the following contract outputs the given error:

```Vyper
@external
def test():
    a:int256 = min(min_value(int256),max_value(int256))
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/output.py", line 82, in build_ir_output
    return compiler_data.ir_nodes
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
  File "/Users/trocher/Documents/thesis/vyper/vyper/compiler/phases.py", line 228, in generate_folded_ast
    vy_ast.folding.fold(vyper_module_folded)
  File "/Users/trocher/Documents/thesis/vyper/vyper/ast/folding.py", line 43, in fold
    changed_nodes += replace_builtin_functions(vyper_module)
  File "/Users/trocher/Documents/thesis/vyper/vyper/ast/folding.py", line 131, in replace_builtin_functions
    new_node = func.evaluate(node)  # type: ignore
  File "/Users/trocher/Documents/thesis/vyper/vyper/builtins/functions.py", line 2019, in evaluate
    raise TypeMismatch("Cannot perform action between dislike numeric types", node)
vyper.exceptions.TypeMismatch: Cannot perform action between dislike numeric types
  contract "tests/customs/code.vy:3", function "test", line 3:15
       2 def test():
  ---> 3     a:int256 = min(min_value(int256),max_value(int256))
  ----------------------^
       4
```

### Additional contract requirements

- `min(a, b)` and `max(a, b)` accept two arguments that share a common numeric type and return the minimum or maximum, preserving that type. They must not raise `TypeMismatch` when both arguments have the same signed integer type, even when one argument is negative and the other is greater than or equal to `2 ** 127`. For example, `min(min_value(int256), max_value(int256))` evaluates to `min_value(int256)`, and `max(min_value(int256), max_value(int256))` evaluates to `max_value(int256)`.
- `min(a, b)` and `max(a, b)` raise `TypeMismatch` when the two arguments have different numeric types, for example `int16` and `int8`.
