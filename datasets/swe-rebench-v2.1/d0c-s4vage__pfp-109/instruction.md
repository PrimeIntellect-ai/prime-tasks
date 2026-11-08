Memcmp is not implemented
After creating the issue, checkboxes will appear where `[] label` exist in the
markdown. You can check/uncheck them to fill out the environment section.

## Checklist

- [ ] I have included the [relevant portions of the] 010 template used that caused the bug
- [ ] I have filled out the environment section

## Environment

**Platform**

- [ ] Windows
- [ ] Mac
- [ ] Linux
- [ ] Other (please specify)

**Python Version**

- [ ] Python 2.7
- [ ] Python 3.4
- [ ] Python 3.5
- [ ] Python 3.6
- [ ] Python 3.7
- [ ] Python 3.8
- [ ] Other (please specify)

## Describe the bug

Memcmp isn't implemented

## Stack Trace

```
Traceback (most recent call last):
  File "/tmp/venv3/bin/pfp", line 8, in <module>
    sys.exit(main())
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/__main__.py", line 55, in main
    keep_successful=args.keep,
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/__init__.py", line 91, in parse
    printf=printf,
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 788, in parse
    res = self._run(keep_successful)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 992, in _run
    traceback,
  File "/tmp/venv3/lib/python3.6/site-packages/six.py", line 695, in reraise
    raise value.with_traceback(tb)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 965, in _run
    res = self._handle_node(self._ast, None, None, self._stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1074, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1117, in _handle_file_ast
    self._handle_node(child, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1074, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 2341, in _handle_while
    self._handle_node(node.stmt, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1074, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 2155, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1074, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1339, in _handle_decl
    field._pfp__init(stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 126, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1074, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1636, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1074, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 2283, in _handle_if
    cond = self._handle_node(node.cond, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1074, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1802, in _handle_binary_op
    left_val = self._handle_node(node.left, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 1074, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/interp.py", line 2122, in _handle_func_call
    return func.call(func_args, ctxt, scope, stream, self, node.coord)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/functions.py", line 79, in call
    res = self.func(args, ctxt, scope, stream, coord)
  File "/tmp/venv3/lib/python3.6/site-packages/pfp/native/compat_string.py", line 140, in Memcmp
    raise NotImplementedError()
pfp.errors.PfpError:
Exception at tests/templates/MP4.bt:53
```

## To Reproduce

Use the MP4.bt template from https://github.com/d0c-s4vage/py010parser/issues/17 ([MP4.txt](https://github.com/d0c-s4vage/py010parser/files/745661/MP4.txt))

## Expected Behavior

The MP4 template should be able to be used.

## Implementation/Fix Notes/Thoughts

[HIDDEN]
