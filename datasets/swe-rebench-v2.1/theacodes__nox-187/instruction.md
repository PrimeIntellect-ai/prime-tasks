Re-factor how Nox documents and stores command line flags
As brought up in #145 (and #147), it's cumbersome to manage the flags and their documentation. There are several locations where new flags have to be updated:

1. `usage.rst`.
2. `__main__.py` (several spots).
3. `test_main.py`
4. `test_sessions.py` (usually).

Preferably, we'd have one source of truth for the name, type, and description of these args. We'd use this source of truth to generate the rest.

### Additional contract requirements

- Add a module `nox._option_set` that provides:
  - `Option(name, *flags, help=None, group=None, noxfile=False, merge_func=None, finalizer_func=None, default=None, hidden=False, **kwargs)`: a single configurable option.
  - `OptionSet(*args, **kwargs)` with:
    - `add_options(*options)`: register `Option` instances with the set.
    - `namespace(**kwargs)`: return an `argparse.Namespace` containing every option's default value, overridden by the supplied keyword values; raise `KeyError` when a supplied name is not a defined option.
- `nox._options.options` is an `OptionSet` instance that exposes `namespace(**kwargs)`.
- The command-line flags `--force-color` and `--no-color` are accepted as aliases for `--forcecolor` and `--nocolor`, setting `config.color` to `True` and `False` respectively.
- Supplying both `--forcecolor` and `--nocolor` rejects the combination, writes an error containing `color` to stderr, and exits with a non-zero status.
