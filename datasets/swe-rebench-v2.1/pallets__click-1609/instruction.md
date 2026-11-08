detection of program name when run with `python -m`
The program name (referred to as `prog_name` or `info_name`) is the name Click uses in usage help text. If it's not specified, Click tries to detect it by looking at `sys.argv[0]`.

https://github.com/pallets/click/blob/dfb842d95a7c146d8fe8140c8100065410d95c4d/src/click/core.py#L797-L800

This works when the CLI is run as a script, either directly, or indirectly as an entry point, or as a module when the program is a single file, but fails when the program is a package and run with `python -m`. In that case, Python converts the `-m name` to the Python file within the package that would be executed. (The use of `__file__` there is also incorrect, as that will always point to `click/core.py`. There should never be a case where `sys.argv` is empty. `make_str` is probably not needed either.)

This leads to the following names:

* `python example.py`, executing a script directly - `example.py`
* `python -m example`, the single file module `example.py` - `example.py`
* `python -m example`, a package like `example/__main__.py` - `__main__.py`
* `python -m example.cli`, a submodule like `example/cli.py` - `cli.py`
* `example`, an entry point, with any of the layouts above - `example`

What's usually expected is that executing a script will print the Python file name (`example.py`), executing an entry point will print the entry point name (`example`), and executing a module or package will print the Python command (`python -m example`, `python -m example.cli`)

This leads to projects that expect to be run as either an entry point or `-m` writing their own wrapper around the CLI to control what name gets used. For example, Flask uses a wrapper that the entry point will call with no args, while `__main__.py` or `__name__ == "__main__"` will pass `as_module=True`.

```python
def main(as_module=False):
    cli.main(prog_name="python -m flask" if as_module else None)
```

Unfortunately, detecting whether `python -m` was used is really, really complicated. Luckily, I did the work already in Werkzeug's reloader: https://github.com/pallets/werkzeug/blob/102bcda52176db448d383a9ef1ccf7e406a379eb/src/werkzeug/_reloader.py#L59. It won't be quite the same in Click because we're not concerned with the exact path to the `python` command or script file, or with arguments, but that should be a good start. Write a function `detect_program_name()` to detect this and call it in place of the existing code.

### Additional contract requirements

- The detector is exposed as `click.utils._detect_program_name(path=None, _main=sys.modules["__main__"])`.
- When `path` is omitted, it falls back to `sys.argv[0]`.
- When `_main` is omitted, it uses the running `__main__` module.
- The required outputs are:
  - `python example.py` (script) -> `example.py`
  - `python -m example` where `example.py` is a single-file module -> `python -m example`
  - `python -m example` where `example/__main__.py` is a package -> `python -m example`
  - `python -m example.cli` where `example/cli.py` is a submodule -> `python -m example.cli`
  - `example` (entry point) -> `example`
- Click existing program-name inference (used when `prog_name` is not given) must call this detector, so help text shows the detected name.
