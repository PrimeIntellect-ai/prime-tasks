conda bin_paths are missing `Library\...` subdirectories on windows
<!-- Thank you for filing a bug! Please feel free to answer as much or as little of this template as you can. -->

**Describe the bug**

When running python code that requires external executables from `conda` packages - i.e. `ipopt`, they cannot be found on the PATH.

**How to reproduce**

This noxfile fails - it should find 'ipopt.exe' on the PATH:
```python
import nox

@nox.session(python="3.7", venv_backend="conda")
def conda_path_bug(session):
    session.conda_install("conda-forge::ipopt==3.11.1")
    session.run("python", "-c", "import shutil; assert shutil.which('ipopt')")
```


**Expected behavior**

The PATH should be set to include the same entries as Anaconda's `cwp.py` provides:
```python
[HIDDEN]
env['CONDA_PREFIX'] = prefix
```

### Additional contract requirements

- On Windows, the paths added to PATH for a conda environment must include the environment root and its `Library\mingw-w64\bin`, `Library\usr\bin`, `Library\bin`, and `Scripts` directories, so executables installed there, such as `ipopt.exe`, can be found.
