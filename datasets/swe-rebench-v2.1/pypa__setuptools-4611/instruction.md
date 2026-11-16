[BUG] Please make trove classifiers validation optional
### setuptools version

from git, also 70.0.0

### Python version

Python 3.12

### OS

Gentoo Linux

### Additional environment information

_No response_

### Description

I tried building a wheel for a package that uses a trove classifier in the very latest version of the trove_classifiers package. Setuptools detected that trove_classifiers was installed, and insisted on validating it.

Looking at the code which handles this, it offers an escape hatch only to "avoid hitting the network" if trove_classifiers is NOT installed: https://github.com/pypa/setuptools/blob/34f9518ef5b50d546893fc29386d4d11866dd9db/setuptools/config/_validate_pyproject/formats.py#L156-L214



### Expected behavior

A way to disable the unwanted functionality without first uninstalling other packages. For example, instead of $VALIDATE_PYPROJECT_NO_NETWORK, I would like to see $VALIDATE_PYPROJECT_NO_TROVE_CLASSIFIERS.

### How to Reproduce

1. git clone https://github.com/urschrei/pyzotero
2. python -m build -nwx

### Output

```console
* Building wheel...
configuration error: `project.classifiers[10]` must be trove-classifier
DESCRIPTION:
    `PyPI classifier <https://pypi.org/classifiers/>`_.

GIVEN VALUE:
    "License :: OSI Approved :: Blue Oak Model License (BlueOak-1.0.0)"

OFFENDING RULE: 'format'

DEFINITION:
    {
        "type": "string",
        "format": "trove-classifier"
    }

For more details about `format` see
https://validate-pyproject.readthedocs.io/en/latest/api/validate_pyproject.formats.html

Traceback (most recent call last):
  File "/usr/lib/python3.12/site-packages/pyproject_hooks/_in_process/_in_process.py", line 373, in <module>
    main()
  File "/usr/lib/python3.12/site-packages/pyproject_hooks/_in_process/_in_process.py", line 357, in main
    json_out["return_val"] = hook(**hook_input["kwargs"])
                             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/site-packages/pyproject_hooks/_in_process/_in_process.py", line 271, in build_wheel
    return _build_backend().build_wheel(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/site-packages/setuptools/build_meta.py", line 410, in build_wheel
    return self._build_with_temp_dir(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/site-packages/setuptools/build_meta.py", line 395, in _build_with_temp_dir
    self.run_setup()
  File "/usr/lib/python3.12/site-packages/setuptools/build_meta.py", line 311, in run_setup
    exec(code, locals())
  File "<string>", line 12, in <module>
  File "/usr/lib/python3.12/site-packages/setuptools/__init__.py", line 103, in setup
    return distutils.core.setup(**attrs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/site-packages/setuptools/_distutils/core.py", line 158, in setup
    dist.parse_config_files()
  File "/usr/lib/python3.12/site-packages/setuptools/dist.py", line 632, in parse_config_files
    pyprojecttoml.apply_configuration(self, filename, ignore_option_errors)
  File "/usr/lib/python3.12/site-packages/setuptools/config/pyprojecttoml.py", line 68, in apply_configuration
    config = read_configuration(filepath, True, ignore_option_errors, dist)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/site-packages/setuptools/config/pyprojecttoml.py", line 133, in read_configuration
    validate(subset, filepath)
  File "/usr/lib/python3.12/site-packages/setuptools/config/pyprojecttoml.py", line 57, in validate
    raise ValueError(f"{error}\n{summary}") from None
ValueError: invalid pyproject.toml config: `project.classifiers[10]`.
configuration error: `project.classifiers[10]` must be trove-classifier

ERROR Backend subprocess exited when trying to invoke build_wheel
```
