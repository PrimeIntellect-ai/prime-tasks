Implicit (duplicate) arrays aren't working if not accessed as a struct/union's child
## Describe the bug

Implicit arrays are working fine when accessed through a struct. However, when accessed through the scope only, they do not work. This problem was noticed when testing the PNG.bt template

E.g.

```c
typedef struct {
    char a_byte;
    Printf("%02x|", item[0].a_byte);
} simple_struct;

while (!FEof()) {
    simple_struct item;
}
```

referencing the `item` variable directly instead of using `__root.item` causes the variable lookup to go down a different code path which doesn't handle implicit arrays correctly.

## Stack Trace

```
$> python -m pfp -t tests/templates/PNG.bt ~/Downloads/test.png
Traceback (most recent call last):
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1024, in _run
    res = self._handle_node(self._ast, None, None, self._stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1177, in _handle_file_ast
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2430, in _handle_while
    self._handle_node(node.stmt, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2244, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1403, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1701, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2378, in _handle_if
    return self._handle_node(node.iffalse, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2375, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2244, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1269, in _handle_decl
    field = self._handle_node(node.type, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1656, in _handle_struct_call_type_decl
    struct_args = self._handle_node(node.args, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2224, in _handle_expr_list
    self._handle_node(expr, scope, ctxt, stream) for expr in node.exprs
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2224, in <listcomp>
    self._handle_node(expr, scope, ctxt, stream) for expr in node.exprs
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1571, in _handle_struct_ref
    struct = self._handle_node(node.name, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1133, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1574, in _handle_struct_ref
    sub_field = getattr(struct, node.field.name)
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 981, in __getattr__
    return super(Struct, self).__getattribute__(name)
AttributeError: 'PNG_CHUNK' object has no attribute 'ihdr'
```

## To Reproduce

Run the PNG.bt template on a PNG image.

The template script below also demonstrates the problem:

```c
typedef struct {
    char a_byte;
    Printf("%02x|", item[0].a_byte);
} simple_struct;

while (!FEof()) {
    simple_struct item;
}
```

The output of the above template script should be `0|0|0|0|`

## Implementation/Fix Notes/Thoughts

The test case below demonstrates the error:

```python
    def test_array_with_root_scope(self):
        dom = self._test_parse_build(
            "\x00\x01\x02\x03",
            """
                typedef struct {
                    char a_byte;
                    Printf("%02x|", item[0].a_byte);
                } simple_struct;

                while (!FEof()) {
                    simple_struct item;
                }
            """,
            stdout="00|00|00|00|",
        )
```

with the result being:

```
_____________________________ TestArrays.test_array_with_root_scope_with_string_data _____________________________
[gw1] linux -- Python 3.6.8 /home/james/__ws__/dev/pfp/venv3/bin/python3
Traceback (most recent call last):
  File "/home/james/__ws__/dev/pfp/tests/test_arrays.py", line 334, in test_array_with_root_scope
    stdout="00|00|00|00|",
  File "/home/james/__ws__/dev/pfp/tests/utils.py", line 53, in _test_parse_build_with_string
    return self._test_parse_build_orig(*args, **kwargs)
  File "/home/james/__ws__/dev/pfp/tests/utils.py", line 81, in _test_parse_build
    self.assertEqual(output, stdout)
  File "/usr/lib/python3.6/unittest/case.py", line 829, in assertEqual
    assertion_func(first, second, msg=msg)
  File "/usr/lib/python3.6/unittest/case.py", line 1203, in assertMultiLineEqual
    self.fail(self._formatMessage(msg, standardMsg))
  File "/usr/lib/python3.6/unittest/case.py", line 670, in fail
    raise self.failureException(msg)
AssertionError: '00|01|02|03|' != '00|00|00|00|'
- 00|01|02|03|
?     ^  ^  ^
+ 00|00|00|00|
?     ^  ^  ^
```
