`pdm remove` does not handle dependency groups properly
### Describe the bug

When running `pdm remove` to remove a package from a dependency group, and this dependency group contains an `include-group` table, `pdm` will error out with `[AttributeError]: 'InlineTable' object has no attribute 'startswith'`.

### To reproduce

```
mkdir pdm-mcve
cd pdm-mcve
cat << EOF > pyproject.toml
[project]
name = "rc-adc"
description = "Resistor Capacitor Analog-to-Digital Converter, written in Amaranth."
authors = [
    {name = "William D. Jones", email = "thor0505@comcast.net"},
]
dependencies = [
    "amaranth>=0.5.3",
]
requires-python = ">=3.10"  # 3.10 for meaningful PyPy notebook support.
readme = "README.md"
license = {text = "BSD-2-Clause license"}
dynamic = ["version"]

[project.optional-dependencies]
daq = [
    "boneless-cpu @ git+https://github.com/whitequark/Boneless-CPU.git",
    "tqdm>=4.67.1",
]
[build-system]
requires = ["pdm-backend"]
build-backend = "pdm.backend"

# pdm.lock may need to be manually tweaked until
# https://github.com/pdm-project/pdm/issues/3426 is resolved.
[tool.pdm.resolution.overrides]
amaranth = "git+https://github.com/amaranth-lang/amaranth.git@v0.5.x"

[dependency-groups]
examples = [
    "rc-adc[daq]"
]
# "pdm run python -m ensurepip" for VSCode!
# pdm venv create -v -n notebook pypy@3.10 --copies if using PyPy.
# You'll be in a world of pain without it!
notebook = [
    "tqdm>=4.67.1",
    { include-group = "examples" },
]
EOF
pdm lock
pdm remove -G notebook tqdm
```

This will result in the following error:

```
Removing packages from notebook dependencies: tqdm
[AttributeError]: 'InlineTable' object has no attribute 'startswith'
WARNING: Add '-v' to see the detailed traceback
```

### Expected Behavior

Actually, other than to ignore the dependency group and continue to the next line, I'm not sure what the correct behavior here should be. Otherwise, since I know the immediate issue/easiest fix, I'd make a PR myself :).

### Environment Information

```
(adc-3.10) william@xubuntu-dtrain:/tmp/pdm-mcve$ pdm info && pdm info --env
PDM version:
  2.23.0
Python Interpreter:
  /tmp/pdm-mcve/.venv/bin/python (3.10)
Project Root:
  /tmp/pdm-mcve
Local Packages:

{
  "implementation_name": "cpython",
  "implementation_version": "3.10.12",
  "os_name": "posix",
  "platform_machine": "x86_64",
  "platform_release": "5.15.0-122-generic",
  "platform_system": "Linux",
  "platform_version": "#132-Ubuntu SMP Thu Aug 29 13:45:52 UTC 2024",
  "python_full_version": "3.10.12",
  "platform_python_implementation": "CPython",
  "python_version": "3.10",
  "sys_platform": "linux"
}
```

### Verbose Command Output

```
(adc-3.10) william@xubuntu-dtrain:/tmp/pdm-mcve$ pdm remove -v -G notebook tqdm
Removing packages from notebook dependencies: tqdm
Traceback (most recent call last):
  File "/home/william/.local/bin/pdm", line 8, in <module>
    sys.exit(main())
  File "/home/william/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/core.py", line 392, in main
    return core.main(args or sys.argv[1:])
  File "/home/william/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/core.py", line 270, in main
    raise cast(Exception, err).with_traceback(traceback) from None
  File "/home/william/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/core.py", line 265, in main
    self.handle(project, options)
  File "/home/william/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/core.py", line 195, in handle
    command.handle(project, options)
  File "/home/william/.local/pipx/venvs/pdm/lib/python3.10/site-packages/pdm/cli/commands/remove.py", line 60, in handle
    self.do_remove(
  [HIDDEN]
  [HIDDEN]
AttributeError: 'InlineTable' object has no attribute 'startswith'
```

### Additional Context

Related to #3336?

### Are you willing to submit a PR to fix this bug?

- [x] Yes, I would like to submit a PR.

### Additional contract requirements

- When `pdm remove` removes a requested package from a dependency group containing an `include-group` entry, it must process that entry without crashing and complete the requested removal.
