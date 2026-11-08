Chained assignments don't work
## Describe the bug

Chained assignments (`a = b = c`) don't work in pfp.

## Stack Trace

```
Traceback (most recent call last):
  File "/home/james/__ws__/dev/pfp/tests/utils.py", line 37, in new_method
    res = method(self, *args, **kwargs)
  File "/home/james/__ws__/dev/pfp/tests/test_control_flow.py", line 334, in test_chained_assignment
    """,
  File "/home/james/__ws__/dev/pfp/tests/utils.py", line 53, in _test_parse_build_with_string
    return self._test_parse_build_orig(*args, **kwargs)
  File "/home/james/__ws__/dev/pfp/tests/utils.py", line 76, in _test_parse_build
    data, template, debug=debug, predefines=predefines, printf=printf
  File "/home/james/__ws__/dev/pfp/tests/../pfp/__init__.py", line 91, in parse
    printf=printf,
  File "/home/james/__ws__/dev/pfp/tests/../pfp/interp.py", line 819, in parse
    res = self._run(keep_successful)
  File "/home/james/__ws__/dev/pfp/tests/../pfp/interp.py", line 1024, in _run
    traceback,
  File "/home/james/__ws__/dev/pfp/tests/../pfp/interp.py", line 997, in _run
    res = self._handle_node(self._ast, None, None, self._stream)
  File "/home/james/__ws__/dev/pfp/tests/../pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/tests/../pfp/interp.py", line 1149, in _handle_file_ast
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/tests/../pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/tests/../pfp/interp.py", line 2072, in _handle_assignment
    res = switch[node.op](field, value)
  File "/home/james/__ws__/dev/pfp/tests/../pfp/interp.py", line 2044, in assign_op
    x._pfp__set_value(y)
  File "/home/james/__ws__/dev/pfp/tests/../pfp/fields.py", line 1613, in _pfp__set_value
    promoted = self._pfp__promote(new_val)
  File "/home/james/__ws__/dev/pfp/tests/../pfp/fields.py", line 1599, in _pfp__promote
    val += -(min_val)
PfpError: TypeError: unsupported operand type(s) for +=: 'NoneType' and 'int'
Exception at string:6
```

## To Reproduce

Run the test below:

```python
    def test_chained_assignment(self):
        dom = self._test_parse_build(
            "",
            """
                local int b = 10;
                local int c;
                local int d;

                c = d = b;
            """,
        )
```

## Expected Behavior

Chained assignments should work.
