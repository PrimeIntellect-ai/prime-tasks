pip-audit crashes with unusual Python versions
does #139 also address python itself having a version like `3.9.7+`? this is what development python versions like `3.9-dev` built via `pyenv` end up with – not sure if this is python's or pyenv's doing.

the stack trace looks different:

```
$ pip-audit
Traceback (most recent call last):
  File "bin/pip-audit", line 5, in <module>
    from pip_audit._cli import audit
  File "lib/python3.9/site-packages/pip_audit/_cli.py", line 15, in <module>
    from pip_audit._audit import AuditOptions, Auditor
  File "lib/python3.9/site-packages/pip_audit/_audit.py", line 9, in <module>
    from pip_audit._dependency_source import DependencySource
  File "lib/python3.9/site-packages/pip_audit/_dependency_source/__init__.py", line 13, in <module>
    from .resolvelib import ResolveLibResolver  # noqa: F401
  File "lib/python3.9/site-packages/pip_audit/_dependency_source/resolvelib/__init__.py", line 5, in <module>
    from .resolvelib import ResolveLibResolver, ResolveLibResolverError  # noqa: F401
  File "lib/python3.9/site-packages/pip_audit/_dependency_source/resolvelib/resolvelib.py", line 16, in <module>
    from .pypi_provider import PyPIProvider
  File "lib/python3.9/site-packages/pip_audit/_dependency_source/resolvelib/pypi_provider.py", line 31, in <module>
    PYTHON_VERSION = Version(python_version())
  File "lib/python3.9/site-packages/packaging/version.py", line 266, in __init__
    raise InvalidVersion(f"Invalid version: '{version}'")
packaging.version.InvalidVersion: Invalid version: '3.9.7+'
```

_Originally posted by @wbolster in https://github.com/trailofbits/pip-audit/issues/138#issuecomment-984603768_

### Additional contract requirements

Initializing the dependency resolver must not crash when the interpreter reports a Python version string that is not valid under PEP 440, such as `3.9.7+`.
