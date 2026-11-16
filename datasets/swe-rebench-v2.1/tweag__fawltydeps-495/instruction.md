environment.yml with pip and -e .
**Describe the bug**
pip with -e ./ in an environment.yml file causes:

```
ERROR:fawltydeps.extract_deps.environment_yml_parser:Failed to parse Pip dependencies in environment.yml: Expected package name at the start of dependency specifier
    -e ./
    ^

```

**To Reproduce**
Steps to reproduce the behavior:


```
name: myenv
channels:
  - conda-forge
dependencies:
  # Core Python and conda packages
  - python=3.12
  - pip
  - setuptools

  # Pip packages
  - pip:
    - -e ./
```

**Expected behavior**
Either just ignore or not throw ERROR

**Environment**
- using micromamba in linux runner for CI
