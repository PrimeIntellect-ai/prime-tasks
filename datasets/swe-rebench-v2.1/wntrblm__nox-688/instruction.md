Support a `NOXPYTHON` environment variable similar to `NOXSESSION`
### How would this feature be useful?

It'd save a few keystrokes and would work as a default for `--pythons`.

### Describe the solution you'd like

Check for `NOXPYTHON` environment variable:

```shell
NOXPYTHON=3.11 nox -s tests
NOXPYTHON=3.10,3.11 nox -s tests
```

While we're at it, it might make sense to also add env vars for `--extra-pythons` and `--force-pythons`.

### Describe alternatives you've considered

Continue using `--pythons`, or include the Python version in `NOXSESSION`, i.e.

```dotenv
NOXSESSION=tests-3.10
```

but this couples the default session with a Python version

### Anything else?

_No response_

### Additional contract requirements

`NOXPYTHON` supplies the default Python-version selection. When a Python-version option is explicitly supplied on the command line, that selection takes precedence over `NOXPYTHON`.
