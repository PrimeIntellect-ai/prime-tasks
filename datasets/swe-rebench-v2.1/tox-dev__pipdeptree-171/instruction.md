AssertionError with -u option
windows 10
Python 3.10.2
pip 21.3.1
pipdeptree 2.2.1

Executing `pipdeptree -u` gives the following:
```
C:\Programs\Python\lib\site-packages\_distutils_hack\__init__.py:17: UserWarning: Distutils was imported before Setuptools, but importing Setuptools also replaces the `distutils` module in `sys.modules`. This may lead to undesirable behaviors or errors. To avoid these issues, avoid using distutils directly, ensure that setuptools is installed in the traditional way (e.g. not an editable install), and/or make sure that setuptools is always imported before distutils.
  warnings.warn(
C:\Programs\Python\lib\site-packages\_distutils_hack\__init__.py:30: UserWarning: Setuptools is replacing distutils.

  warnings.warn("Setuptools is replacing distutils.")
Traceback (most recent call last):
  File "C:\Programs\Python\lib\runpy.py", line 196, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "C:\Programs\Python\lib\runpy.py", line 86, in _run_code
    exec(code, run_globals)
  File "C:\Programs\Python\Scripts\pipdeptree.exe\__main__.py", line 7, in <module>
  File "C:\Programs\Python\lib\site-packages\pipdeptree.py", line 888, in main
    conflicts = conflicting_deps(tree)
  File "C:\Programs\Python\lib\site-packages\pipdeptree.py", line 689, in conflicting_deps
    if req.is_conflicting():
  File "C:\Programs\Python\lib\site-packages\pipdeptree.py", line 231, in is_conflicting
    if self.installed_version == self.UNKNOWN_VERSION:
  File "C:\Programs\Python\lib\site-packages\pipdeptree.py", line 221, in installed_version
    return guess_version(self.key, self.UNKNOWN_VERSION)
  File "C:\Programs\Python\lib\site-packages\pipdeptree.py", line 64, in guess_version
    m = import_module(pkg_key)
  File "C:\Programs\Python\lib\importlib\__init__.py", line 126, in import_module
    return _bootstrap._gcd_import(name[level:], package, level)
  File "<frozen importlib._bootstrap>", line 1050, in _gcd_import
  File "<frozen importlib._bootstrap>", line 1027, in _find_and_load
  File "<frozen importlib._bootstrap>", line 1006, in _find_and_load_unlocked
  File "<frozen importlib._bootstrap>", line 688, in _load_unlocked
  File "<frozen importlib._bootstrap_external>", line 883, in exec_module
  File "<frozen importlib._bootstrap>", line 241, in _call_with_frames_removed
  File "C:\Programs\Python\lib\site-packages\setuptools\__init__.py", line 8, in <module>
    import _distutils_hack.override  # noqa: F401
  File "C:\Programs\Python\lib\site-packages\_distutils_hack\override.py", line 1, in <module>
    __import__('_distutils_hack').do_override()
  File "C:\Programs\Python\lib\site-packages\_distutils_hack\__init__.py", line 71, in do_override
    ensure_local_distutils()
  File "C:\Programs\Python\lib\site-packages\_distutils_hack\__init__.py", line 59, in ensure_local_distutils
    assert '_distutils' in core.__file__, core.__file__
AssertionError: C:\Programs\Python\lib\distutils\core.py
```
Thanks
