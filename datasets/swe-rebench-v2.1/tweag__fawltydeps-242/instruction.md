Different name for pypi package and exposed package
**Describe the bug**
Some packages have the same name, but are imported by a different name. For example python-dotenv

![image](https://user-images.githubusercontent.com/127505435/225351304-7d866612-37c6-412d-9aee-a89569b4d149.png)


**To Reproduce**
Install python-dotenv and add the following example.

```py
from dotenv import load_dotenv

load_dotenv()  # take environment variables from .env.
```

**Expected behavior**
As a result, we don't see unused and undeclared dependencies

**Environment**
 - OS name + version: NixOS 23.05.20230301.a08d697 (Stoat) x86_64
 - Version of the code: 0201e74a158c5774db9150e1e70f01e76bad34e7

### Additional contract requirements

- The command-line option that selects the Python environment used to map
  dependency names to import names is `--pyenv` (replacing the former `--venv`).
  The corresponding configuration directive is `pyenv`.
- `fawltydeps.packages.LocalPackageLookup` accepts an optional `pyenv_path`
  argument (`Optional[Path]`, default `None`). When it is omitted or `None`, the
  current Python environment is used. When a supplied path does not point to a
  Python environment, a `ValueError` is raised.
- `fawltydeps.packages.LocalPackageLookup.determine_package_dir(path: Path) -> Optional[Path]`
  is a class method that returns the `site-packages` directory of the Python
  environment that contains the given path, accepting both the environment root
  and paths nested inside it, or `None` when no Python environment can be
  deduced.
- `fawltydeps.packages.resolve_dependencies(dep_names: Iterable[str], pyenv_path: Optional[Path] = None) -> Dict[str, Package]`
  maps each declared dependency name to a `Package` describing the import names
  it provides, using the environment given by `pyenv_path` (or the current
  Python environment when `None`). Dependencies that cannot be found fall back
  to an identity mapping.
