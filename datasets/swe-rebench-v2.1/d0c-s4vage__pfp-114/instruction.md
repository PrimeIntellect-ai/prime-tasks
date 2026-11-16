Enums and [HIDDEN] error
After creating the issue, checkboxes will appear where `[] label` exist in the
markdown. You can check/uncheck them to fill out the environment section.

## Describe the bug

A clear and concise description of what the bug is.

## Stack Trace

Stack traces are required

```
python -m pfp -t DEX.bt ~/Downloads/classes.dex --pdb
usage: pfp [-h] -t TEMPLATE [-k] input
pfp: error: unrecognized arguments: --pdb
(venv3)  lptp [ pfp ]: python -m pfp -t DEX.bt ~/Downloads/classes.dex
Traceback (most recent call last):
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 997, in _run
    res = self._handle_node(self._ast, None, None, self._stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1149, in _handle_file_ast
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 57, in _pfp__init
    super(self.__class__, self)._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1375, in _handle_decl
    stream, metadata_processor=metadata_processor
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 196, in __init__
    metadata_processor=metadata_processor,
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 2048, in __init__
    self._pfp__parse(stream, save_offset=True)
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 2187, in _pfp__parse
    field = self.field_cls(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 147, in __init__
    self._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2318, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2318, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 57, in _pfp__init
    super(self.__class__, self)._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2344, in _handle_for
    self._handle_node(node.stmt, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 57, in _pfp__init
    super(self.__class__, self)._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2318, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2318, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2400, in _handle_do_while
    node.cond, scope, ctxt, stream
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1840, in _handle_binary_op
    res = switch[node.op](left_val, right_val)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1828, in <lambda>
    "!=": lambda x, y: x != y,
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 1678, in __ne__
    cmp_self, cmp_other = self._pfp__maybe_promote(self, other)
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 1533, in _pfp__maybe_promote
    res = (val1, val1._pfp__promote(val2))
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 1586, in _pfp__promote
    [HIDDEN]

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/lib/python3.6/runpy.py", line 193, in _run_module_as_main
    "__main__", mod_spec)
  File "/usr/lib/python3.6/runpy.py", line 85, in _run_code
    exec(code, run_globals)
  File "/home/james/__ws__/dev/pfp/pfp/__main__.py", line 61, in <module>
    main(sys.argv)
  File "/home/james/__ws__/dev/pfp/pfp/__main__.py", line 55, in main
    keep_successful=args.keep,
  File "/home/james/__ws__/dev/pfp/pfp/__init__.py", line 91, in parse
    printf=printf,
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 819, in parse
    res = self._run(keep_successful)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1024, in _run
    traceback,
  File "/home/james/__ws__/dev/pfp/venv3/lib/python3.6/site-packages/six.py", line 695, in reraise
    raise value.with_traceback(tb)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 997, in _run
    res = self._handle_node(self._ast, None, None, self._stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1149, in _handle_file_ast
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 57, in _pfp__init
    super(self.__class__, self)._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1375, in _handle_decl
    stream, metadata_processor=metadata_processor
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 196, in __init__
    metadata_processor=metadata_processor,
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 2048, in __init__
    self._pfp__parse(stream, save_offset=True)
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 2187, in _pfp__parse
    field = self.field_cls(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 147, in __init__
    self._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2318, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2318, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 57, in _pfp__init
    super(self.__class__, self)._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2344, in _handle_for
    self._handle_node(node.stmt, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 57, in _pfp__init
    super(self.__class__, self)._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2318, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2318, in _handle_if
    return self._handle_node(node.iftrue, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2187, in _handle_compound
    self._handle_node(child, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1371, in _handle_decl
    field._pfp__init(stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 150, in _pfp__init
    self._pfp__interp._handle_node(decls, ctxt=self, stream=stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1668, in _handle_struct_decls
    self._handle_node(decl, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 2400, in _handle_do_while
    node.cond, scope, ctxt, stream
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1106, in _handle_node
    res = self._node_switch[node.__class__](node, scope, ctxt, stream)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1840, in _handle_binary_op
    res = switch[node.op](left_val, right_val)
  File "/home/james/__ws__/dev/pfp/pfp/interp.py", line 1828, in <lambda>
    "!=": lambda x, y: x != y,
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 1678, in __ne__
    cmp_self, cmp_other = self._pfp__maybe_promote(self, other)
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 1533, in _pfp__maybe_promote
    res = (val1, val1._pfp__promote(val2))
  File "/home/james/__ws__/dev/pfp/pfp/fields.py", line 1586, in _pfp__promote
    [HIDDEN]
Exception at DEX.bt:1417
```

## To Reproduce

Use the [DEX.bt template](https://www.sweetscape.com/010editor/repository/files/DEX.v1.2.bt) on the [classes.dex](https://github.com/google/enjarify/blob/02c417d33da3c237ecf65afe84d4fb0c6f1b4286/tests/test2/classes.dex) referenced by #14

## Expected Behavior

Should be able to use the DEX.bt template with no errors

## Implementation/Fix Notes/Thoughts

I think it's something simple

### Additional contract requirements

- Enum comparisons used by the DEX.bt template must complete without raising an exception.
