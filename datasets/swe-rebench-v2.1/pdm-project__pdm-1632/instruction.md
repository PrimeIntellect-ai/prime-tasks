[BUG] Invalid version spec `>=5.*, <=6.*` creates unhandled junk dependency `b''`
- [X] I have searched the issue tracker and believe that this is not a duplicate.

**Make sure you run commands with `-v` flag before pasting the output.**

## Steps to reproduce

`pdm add pyaml-env==1.2.0` with a fresh `pyproject.toml` like the following:

```toml
[project]
name = ""
version = ""
description = ""
authors = [
    {name = "Gregory Danielson", email = "gregory.danielson3@gmail.com"},
]
dependencies = []
requires-python = ">=3.6"
license = {text = "MIT"}

[tool.pdm]
```

You can also set up a minimal project with the following `setup.py` and attempt to install it:

```py
from setuptools import setup

REQUIREMENTS = ["PyYAML>=5.*"]

setup(name="project",
      version="0.1.0",
      install_requires=REQUIREMENTS,
      package_dir={"": "src"},
      packages=["project"])

```

## Actual behavior

```
pdm.termui: ======== Starting round 1 ========
unearth.preparer: Using cached <Link https://files.pythonhosted.org/packages/d2/6c/fb09236297c1934448966abed6aaa2b2bed9f78992ef0346343e326398f4/pyaml_env-1.2.0-py3-none-any.whl (from https://pypi.org/simple/pyaml-env/)>
pdm.termui:   Adding requirement b''(from pyaml-env 1.2.0)
[FileRequirement(name=None, marker=None, extras=None, specifier=None, editable=False, prerelease=False, url=None, path=PosixPath("b''"), subdirectory=None)]
Traceback (most recent call last):
  File "/home/gregdan3/.local/bin/pdm", line 8, in <module>
    sys.exit(main())
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/core.py", line 259, in main
    return Core().main(args)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/core.py", line 191, in main
    raise cast(Exception, err).with_traceback(traceback)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/core.py", line 186, in main
    f(project, options)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/cli/commands/install.py", line 58, in handle
    actions.do_lock(
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/cli/actions.py", line 95, in do_lock
    mapping, dependencies = resolve(
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/resolver/core.py", line 35, in resolve
    result = resolver.resolve(requirements, max_rounds)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/resolvelib/resolvers.py", line 521, in resolve
    state = resolution.resolve(requirements, max_rounds=max_rounds)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/resolvelib/resolvers.py", line 402, in resolve
    failure_causes = self._attempt_to_pin_criterion(name)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/resolvelib/resolvers.py", line 238, in _attempt_to_pin_criterion
    criteria = self._get_updated_criteria(candidate)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/resolvelib/resolvers.py", line 229, in _get_updated_criteria
    self._add_to_criteria(criteria, requirement, parent=candidate)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/resolvelib/resolvers.py", line 172, in _add_to_criteria
    if not criterion.candidates:
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/resolvelib/structs.py", line 127, in __bool__
    next(iter(self))
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/resolvelib/structs.py", line 136, in __iter__
    self._factory() if self._iterable is None else self._iterable
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/resolver/providers.py", line 151, in matches_gen
    candidates = self._find_candidates(reqs[0])
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/resolver/providers.py", line 127, in _find_candidates
    can = make_candidate(requirement)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/models/candidates.py", line 626, in make_candidate
    return Candidate(req, name, version, link)
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/models/candidates.py", line 145, in __init__
    link = req.as_file_link()  # type: ignore
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/models/requirements.py", line 321, in as_file_link
    return Link(url)
  File "<string>", line 9, in __init__
  File "/home/gregdan3/.local/pipx/venvs/pdm/lib/python3.10/site-packages/unearth/link.py", line 54, in __post_init__
    if self.url.startswith(vcs_prefixes):
TypeError: a bytes-like object is required, not 'str'
```


## Expected behavior

Version specs such as [those previously in pyaml-env](https://github.com/mkaranasou/pyaml_env/blob/acca18ffbf28ab03cf9aff34ce17db5d09bb2c93/requirements.txt) should be detected as breaking PEP440 rather than assumed to be FileRequirements.

## Environment Information

```bash
# Paste the output of `pdm info && pdm info --env` below:
PDM version:
  2.4.0
Python Interpreter:
  /usr/bin/python3 (3.10)
Project Root:
  /home/gregdan3/example
Project Packages:
  /home/gregdan3/example/__pypackages__/3.10

{
  "implementation_name": "cpython",
  "implementation_version": "3.10.9",
  "os_name": "posix",
  "platform_machine": "x86_64",
  "platform_release": "6.0.12-arch1-1",
  "platform_system": "Linux",
  "platform_version": "#1 SMP PREEMPT_DYNAMIC Thu, 08 Dec 2022 11:03:38 +0000",
  "python_full_version": "3.10.9",
  "platform_python_implementation": "CPython",
  "python_version": "3.10",
  "sys_platform": "linux"
}

```

## Other Notes

`pyaml-env` has already fixed this bug [here](https://github.com/mkaranasou/pyaml_env/issues/30).

[HIDDEN]
The `b''` obviously fails the next round of dependency resolution.

Ideally, there would be an independent way to verify the FileRequirement so it could be more than a secondary case of the PackageRequirement.

### Additional contract requirements

- Parsing `foo >=4.*, <=5.*` and `foo (>=4.*, <=5.*)` must produce the normalized requirement string `foo<5.0,>=4.0`.
- Provide `PACKAGING_22` in `pdm.utils`, a boolean that is true when the installed `packaging` version is at least 22.0.
- A legacy wildcard version requirement such as `PyYAML>=5.*` must be recognized as a package requirement, not misinterpreted as a file requirement.
