Cannot install pgobject, Invalid specifier: '>=3.5.4|^4.2.0'
- [x] I have searched the issue tracker and believe that this is not a duplicate.

**Make sure you run commands with `-v` flag before pasting the output.**

## Steps to reproduce
Install pygobject
```bash
pdm add pygobject
```

## Actual behavior

```bash
Traceback (most recent call last):
  File "/usr/lib/python-exec/python3.11/pdm", line 8, in <module>
    sys.exit(main())
             ^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/core.py", line 290, in main
    return Core().main(args or sys.argv[1:])
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/core.py", line 208, in main
    raise cast(Exception, err).with_traceback(traceback) from None
  File "/usr/lib/python3.11/site-packages/pdm/core.py", line 203, in main
    self.handle(project, options)
  File "/usr/lib/python3.11/site-packages/pdm/core.py", line 157, in handle
    command.handle(project, options)
  File "/usr/lib/python3.11/site-packages/pdm/cli/commands/add.py", line 67, in handle
    self.do_add(
  File "/usr/lib/python3.11/site-packages/pdm/cli/commands/add.py", line 147, in do_add
    all_dependencies = project.all_dependencies
                       ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/project/core.py", line 343, in all_dependencies
    return {group: self.get_dependencies(group) for group in self.iter_groups()}
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/project/core.py", line 343, in <dictcomp>
    return {group: self.get_dependencies(group) for group in self.iter_groups()}
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/project/core.py", line 328, in get_dependencies
    req = parse_requirement(line)
          ^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/models/requirements.py", line 506, in parse_requirement
    r = Requirement.from_pkg_requirement(pkg_req)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/models/requirements.py", line 228, in from_pkg_requirement
    return klass(url=req.url, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "<string>", line 12, in __init__
  File "/usr/lib/python3.11/site-packages/pdm/models/requirements.py", line 255, in __post_init__
    self._check_installable()
  File "/usr/lib/python3.11/site-packages/pdm/models/requirements.py", line 394, in _check_installable
    result = Setup.from_directory(self.path.absolute())
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/models/setup.py", line 37, in from_directory
    return _SetupReader.read_from_directory(dir)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/models/setup.py", line 61, in read_from_directory
    new_result = file_reader(filepath)
                 ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/models/setup.py", line 73, in read_pyproject_toml
    metadata = PyProject(file, ui=termui.UI()).metadata.unwrap()
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/project/toml_file.py", line 18, in __init__
    self._data = self.read()
                 ^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/project/project_file.py", line 32, in read
    metadata, settings = converter.convert(None, self._path, None)
                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/formats/poetry.py", line 204, in convert
    return converter.convert()
           ^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/formats/base.py", line 55, in convert
    self._data[key] = func(self, value)
                      ^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/formats/poetry.py", line 147, in dev_dependencies
    "dev": make_array([r for key, req in value.items() for r in _convert_req(key, req)], True),
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/formats/poetry.py", line 147, in <listcomp>
    "dev": make_array([r for key, req in value.items() for r in _convert_req(key, req)], True),
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/formats/poetry.py", line 74, in _convert_req
    yield Requirement.from_req_dict(name, _convert_specifier(req_dict)).as_line()
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/models/requirements.py", line 180, in from_req_dict
    return NamedRequirement(name=name, specifier=get_specifier(req_dict))
                                                 ^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/pdm/models/specifiers.py", line 28, in get_specifier
    return SpecifierSet(version_str)
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/packaging/specifiers.py", line 714, in __init__
    parsed.add(Specifier(specifier))
               ^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/site-packages/packaging/specifiers.py", line 245, in __init__
    raise InvalidSpecifier(f"Invalid specifier: '{spec}'")
packaging.specifiers.InvalidSpecifier: Invalid specifier: '>=3.5.4|^4.2.0'
```

## Expected behavior

Successful installation

## Environment Information

```bash
PDM version:
  2.8.2
Python Interpreter:
  /tmp/test/.venv/bin/python (3.11)
Project Root:
  /tmp/test
Local Packages:

{
  "implementation_name": "cpython",
  "implementation_version": "3.11.4",
  "os_name": "posix",
  "platform_machine": "x86_64",
  "platform_release": "6.1.31-gentoo-dist",
  "platform_system": "Linux",
  "platform_version": "#1 SMP PREEMPT_DYNAMIC Sun Jun 25 00:30:59 CEST 2023",
  "python_full_version": "3.11.4",
  "platform_python_implementation": "CPython",
  "python_version": "3.11",
  "sys_platform": "linux"
}
```

### Additional contract requirements

- `MetaConvertError` must be importable from `pdm.formats` and must accept the collected error messages, the partial metadata `data` and the conversion `settings`. Its string representation must join the error messages with newlines, and the provided `data` must be preserved on the instance.
- Reading a project's metadata for installation must not abort when poetry-style metadata contains an invalid specifier. In particular, `pdm.models.setup.Setup.from_directory` must return the partial metadata (including the project `name` and `version`) instead of propagating the conversion error, so that installing the reported package can proceed.
