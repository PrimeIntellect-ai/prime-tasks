PIPX_GLOBAL_(HOME|BIN_DIR|MAN_DIR) missing from documentation and `pipx environment`
**Describe the bug**

`pipx environment` does not list `PIPX_GLOBAL_(HOME|BIN_DIR|MAN_DIR)` under `Environment variables (set by user)`. Additionally these variables are missing from the documentation of the `environment` and `install` commands, which makes them pretty hard to discover as a user.

**How to reproduce**

```sh
$ pipx environment
Environment variables (set by user):

PIPX_HOME=
PIPX_BIN_DIR=
PIPX_MAN_DIR=
PIPX_SHARED_LIBS=
PIPX_DEFAULT_PYTHON=
PIPX_FETCH_MISSING_PYTHON=
USE_EMOJI=

Derived values (computed by pipx):

PIPX_HOME=/home/user/.local/share/pipx
PIPX_BIN_DIR=/home/user/.local/bin
PIPX_MAN_DIR=/home/user/.local/share/man
PIPX_SHARED_LIBS=/home/user/.local/share/pipx/shared
PIPX_LOCAL_VENVS=/home/user/.local/share/pipx/venvs
PIPX_LOG_DIR=/home/user/.local/state/pipx/log
PIPX_TRASH_DIR=/home/user/.local/share/pipx/trash
PIPX_VENV_CACHEDIR=/home/user/.cache/pipx
PIPX_STANDALONE_PYTHON_CACHEDIR=/home/user/.local/share/pipx/py
PIPX_DEFAULT_PYTHON=/home/user/local/bin/python3.12
USE_EMOJI=true
```

```sh
$ pipx environment --global
Environment variables (set by user):

PIPX_HOME=
PIPX_BIN_DIR=
PIPX_MAN_DIR=
PIPX_SHARED_LIBS=
PIPX_DEFAULT_PYTHON=
PIPX_FETCH_MISSING_PYTHON=
USE_EMOJI=

Derived values (computed by pipx):

PIPX_HOME=/opt/pipx
PIPX_BIN_DIR=/usr/local/bin
PIPX_MAN_DIR=/usr/local/share/man
PIPX_SHARED_LIBS=/opt/pipx/shared
PIPX_LOCAL_VENVS=/opt/pipx/venvs
PIPX_LOG_DIR=/opt/pipx/logs
PIPX_TRASH_DIR=/opt/pipx/.trash
PIPX_VENV_CACHEDIR=/opt/pipx/.cache
PIPX_STANDALONE_PYTHON_CACHEDIR=/opt/pipx/py
PIPX_DEFAULT_PYTHON=/usr/local/bin/python3.12
USE_EMOJI=true

```

```sh
$ pipx environment --help
usage: pipx environment [-h] [--quiet] [--verbose] [--global] [--value VARIABLE]

[...]

Available variables:
PIPX_HOME, PIPX_BIN_DIR, PIPX_MAN_DIR, PIPX_SHARED_LIBS, PIPX_LOCAL_VENVS,
PIPX_LOG_DIR, PIPX_TRASH_DIR, PIPX_VENV_CACHEDIR, PIPX_DEFAULT_PYTHON, USE_EMOJI, PIPX_HOME_ALLOW_SPACE

[...]
```

**Expected behavior**

```sh
$ pipx environment
Environment variables (set by user):

PIPX_HOME=
PIPX_GLOBAL_HOME=             # <-- added
PIPX_BIN_DIR=
PIPX_GLOBAL_BIN_DIR=          # <-- added
PIPX_MAN_DIR=
PIPX_GLOBAL_MAN_DIR=          # <-- added
PIPX_SHARED_LIBS=
PIPX_DEFAULT_PYTHON=
PIPX_FETCH_MISSING_PYTHON=
USE_EMOJI=
PIPX_HOME_ALLOW_SPACE=

Derived values (computed by pipx):

PIPX_HOME=/home/user/.local/share/pipx
PIPX_BIN_DIR=/home/user/.local/bin
PIPX_MAN_DIR=/home/user/.local/share/man
PIPX_SHARED_LIBS=/home/user/.local/share/pipx/shared
PIPX_LOCAL_VENVS=/home/user/.local/share/pipx/venvs
PIPX_LOG_DIR=/home/user/.local/state/pipx/log
PIPX_TRASH_DIR=/home/user/.local/share/pipx/trash
PIPX_VENV_CACHEDIR=/home/user/.cache/pipx
PIPX_STANDALONE_PYTHON_CACHEDIR=/home/user/.local/share/pipx/py
PIPX_DEFAULT_PYTHON=/usr/local/bin/python3.12
USE_EMOJI=true
PIPX_HOME_ALLOW_SPACE=false
```

```sh
$ pipx environment --global
Environment variables (set by user):

PIPX_HOME=
PIPX_GLOBAL_HOME=             # <-- added
PIPX_BIN_DIR=
PIPX_GLOBAL_BIN_DIR=          # <-- added
PIPX_MAN_DIR=
PIPX_GLOBAL_MAN_DIR=          # <-- added
PIPX_SHARED_LIBS=
PIPX_DEFAULT_PYTHON=
PIPX_FETCH_MISSING_PYTHON=
USE_EMOJI=
PIPX_HOME_ALLOW_SPACE=

Derived values (computed by pipx):

PIPX_HOME=/opt/pipx
PIPX_BIN_DIR=/usr/local/bin
PIPX_MAN_DIR=/usr/local/share/man
PIPX_SHARED_LIBS=/opt/pipx/shared
PIPX_LOCAL_VENVS=/opt/pipx/venvs
PIPX_LOG_DIR=/opt/pipx/logs
PIPX_TRASH_DIR=/opt/pipx/trash
PIPX_VENV_CACHEDIR=/opt/pipx/.cache
PIPX_STANDALONE_PYTHON_CACHEDIR=/opt/pipx/py
PIPX_DEFAULT_PYTHON=/usr/local/bin/python3.12
USE_EMOJI=true
PIPX_HOME_ALLOW_SPACE=false
```

```sh
$ pipx environment --help
usage: pipx environment [-h] [--quiet] [--verbose] [--global] [--value VARIABLE]

[...]

Available variables:
PIPX_HOME, PIPX_GLOBAL_HOME, PIPX_BIN_DIR, PIPX_GLOBAL_BIN_DIR,
PIPX_MAN_DIR, PIPX_GLOBAL_MAN_DIR, PIPX_SHARED_LIBS, PIPX_LOCAL_VENVS,
PIPX_LOG_DIR, PIPX_TRASH_DIR, PIPX_VENV_CACHEDIR, PIPX_DEFAULT_PYTHON,
USE_EMOJI, PIPX_HOME_ALLOW_SPACE

[...]
```

### Additional contract requirements

- The `pipx install --help` output must list `PIPX_GLOBAL_HOME`, `PIPX_GLOBAL_BIN_DIR`, and `PIPX_GLOBAL_MAN_DIR`.
- Add a public constant `ENVIRONMENT_VARIABLES` in module `pipx.commands.environment`. It is a list of strings naming every environment variable that `pipx environment` reports as set by the user.
