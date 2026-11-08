Auto-importing doesn't work with namespace packages (Prop#289079)
```py
$ py3 "print(foopkg)"
[PYFLYBY] import foopkg
[PYFLYBY] print(foopkg)
<module 'foopkg' from '/usr/local/.../python3.7/site-packages/foopkg/__init__.py'
```
Removing `/usr/local/.../python3.7/site-packages/foopkg/__init__.py` will make `foopkg` a namespace. It'll also break the auto-import feature of pyflyby.

```py
$ py3 "print(foopkg)"
Traceback (most recent call last):
  File "/usr/local/bin/py3", line 8, in <module>
    sys.exit(py_main())
  File "/usr/local/.../python3.7/site-packages/pyflyby/_py.py", line 2046, in py_main
    _PyMain(args).run()
  File "/usr/local/.../python3.7/site-packages/pyflyby/_py.py", line 1781, in run
    self._run_action()
  File "/usr/local/.../python3.7/site-packages/pyflyby/_py.py", line 2016, in _run_action
    self.heuristic_cmd(cmd, args, function_name=arg0)
  File "/usr/local/.../python3.7/site-packages/pyflyby/_py.py", line 1539, in heuristic_cmd
    result = self.namespace.auto_eval(cmd, info=info, debug=self.debug)
  File "/usr/local/.../python3.7/site-packages/pyflyby/_py.py", line 1411, in auto_eval
    raise UnimportableNameError(msg)
pyflyby._py.UnimportableNameError: name 'foopkg' is not defined and not importable
```
Manually importing `foopkg` works fine.
```
py$ py3 "import foopkg; print(foopkg)"
[PYFLYBY] import foopkg; print(foopkg)
<module 'foopkg' (namespace)>

```
