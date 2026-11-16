Include Conda-install package functionality
**How would this feature be useful?**
Reading the documentation , nox provides automated pip-install packages feature ( that can be defined in the configuration file).
 It would be useful to support conda-install as well , to be able to include installing miniconda/anaconda package install .

I would like to work on this as my first contribution , if anyone could help me get started, would be really helpful!

### Additional contract requirements

- `nox.session` accepts a `venv_backend` keyword argument whose value is `None`, `"virtualenv"`, or `"conda"`. The decorated session function exposes this value as its `venv_backend` attribute. A session with `venv_backend="conda"` uses a `nox.virtualenv.CondaEnv`; a session with `venv_backend` set to `None` or `"virtualenv"` uses a `nox.virtualenv.VirtualEnv`. Any other `venv_backend` value raises `ValueError` whose message contains `venv_backend`.
- `nox.sessions.Session.conda_install(*packages, silent=True)` installs the given packages into the session's conda environment by running `conda install --yes --prefix <env_location> <packages...>`. It is only valid for a session whose environment is a `nox.virtualenv.CondaEnv`; otherwise it raises `ValueError` whose message contains `conda environment`. Calling it without any packages raises `ValueError` whose message contains `arg`. The install command is run with `external="error"`, and `silent` defaults to `True`.
- `nox.virtualenv.CondaEnv(location, interpreter=None, reuse_existing=False)` is a conda environment class exposing:
  - `location`: the absolute path of the environment.
  - `location_name`: the original `location` value passed to the constructor.
  - `interpreter`: the interpreter value passed to the constructor.
  - `reuse_existing`: the reuse flag passed to the constructor.
  - `is_sandboxed`: `True`.
  - `bin`: `<location>/Scripts` on Windows, otherwise `<location>/bin`.
  - `create()`: removes any pre-existing environment unless `reuse_existing` is set, then runs `conda create --yes --prefix <location> pip <python_dep>`, where `<python_dep>` is `python=<interpreter>` when an interpreter is given and `python` otherwise.
