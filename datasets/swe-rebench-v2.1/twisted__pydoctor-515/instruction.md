Regression after 22.2.2  - reparenting confusion crash
When reparenting a class to a module of the same name, then, the next reparent might to move the object to the class instead of moving it to the module. Leading to AssertionError.

Looks like it's a bug introduced by a combinaison trying to comply with mypy in [this commit](https://github.com/twisted/pydoctor/commit/2a0f98e272842ce1c4a78adbba086ef804ef80be) and [HIDDEN]

```python
[HIDDEN]
```


```python
moving 'Wappalyzer.Wappalyzer.WebPage' into 'Wappalyzer'
moving 'Wappalyzer.Wappalyzer.Wappalyzer' into 'Wappalyzer'
moving 'Wappalyzer.Wappalyzer.analyze' into 'Wappalyzer'
Traceback (most recent call last):
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/bin/pydoctor", line 8, in <module>
    sys.exit(main())
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/driver.py", line 431, in main
    system.process()
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/model.py", line 1031, in process
    self.processModule(mod)
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/model.py", line 1016, in processModule
    builder.processModuleAST(ast, mod)
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/astbuilder.py", line 1[18](https://github.com/chorsley/python-Wappalyzer/runs/5469341311?check_suite_focus=true#step:5:18)2, in processModuleAST
    self.ModuleVistor(self, mod).visit(mod_ast)
  File "/opt/hostedtoolcache/Python/3.8.12/x64/lib/python3.8/ast.py", line 371, in visit
    return visitor(node)
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/astbuilder.py", line 239, in visit_Module
    self.default(node)
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/astbuilder.py", line 2[19](https://github.com/chorsley/python-Wappalyzer/runs/5469341311?check_suite_focus=true#step:5:19), in default
    self.visit(child)
  File "/opt/hostedtoolcache/Python/3.8.12/x64/lib/python3.8/ast.py", line 371, in visit
    return visitor(node)
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/astbuilder.py", line 343, in visit_ImportFrom
    self._importNames(modname, node.names)
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/astbuilder.py", line 412, in _importNames
    ob.reparent(current, asname)
  File "/home/runner/work/python-Wappalyzer/python-Wappalyzer/.tox/docs/lib/python3.8/site-packages/pydoctor/model.py", line [25](https://github.com/chorsley/python-Wappalyzer/runs/5469341311?check_suite_focus=true#step:5:25)2, in reparent
    assert isinstance(old_parent, Module)
AssertionError
```

I'll add a system test with `python-Wappalyzer`.

### Additional contract requirements

- Reparenting must work when an object's existing parent is a class, not a module: moving it to another parent must not raise an `AssertionError`, and the object must belong to the destination rather than remain under its former class.
