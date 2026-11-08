Unable to see EOFError exception in the traceback with disabled standalone mode
According to the [docs](https://click.palletsprojects.com/en/8.0.x/exceptions/?highlight=standalone%20mode#what-if-i-don-t-want-that) disabled standalone mode disables exception handling. However, click still suppresses `EOFError` (as well as `KeyboardInterrupt`) exceptions from the stack trace due to the `raise ... from None` construction, see:

https://github.com/pallets/click/blob/0aec1168ac591e159baf6f61026d6ae322c53aaf/src/click/core.py#L1066-L1068

[HIDDEN]

Real world example. I use asyncio streams that can [raise IncompleteReadError](https://github.com/python/cpython/blob/d03acd7270d66ddb8e987f9743405147ecc15087/Lib/asyncio/exceptions.py#L29) which inherited from `EOFError`, but I can't see the exception in the stack trace even with disabled standalone mode which looks like a bug to me.

**How to replicate the bug:**

1. Create the following script:
```python
# t.py
import click


@click.command()
def cli():
    raise EOFError('I want to see this exception')


if __name__ == '__main__':
    cli.main(standalone_mode=False)
```

2. Run module `python -m t`

**Actual behavior:**

```python
Traceback (most recent call last):
  File "/Users/albert/.pyenv/versions/3.10.4/lib/python3.10/runpy.py", line 196, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "/Users/albert/.pyenv/versions/3.10.4/lib/python3.10/runpy.py", line 86, in _run_code
    exec(code, run_globals)
  File "/private/var/folders/l0/lnq1ghps5yqc4vkgszlcz92m0000gp/T/tmp.X1tRYLrm/t.py", line 10, in <module>
    cli.main(standalone_mode=False)
  File "/private/var/folders/l0/lnq1ghps5yqc4vkgszlcz92m0000gp/T/tmp.X1tRYLrm/.venv/lib/python3.10/site-packages/click/core.py", line 1068, in main
    raise Abort() from None
click.exceptions.Abort
```

**Expected behavior:**

```python
Traceback (most recent call last):
  File "/private/var/folders/l0/lnq1ghps5yqc4vkgszlcz92m0000gp/T/tmp.X1tRYLrm/.venv/lib/python3.10/site-packages/click/core.py", line 1055, in main
    rv = self.invoke(ctx)
  File "/private/var/folders/l0/lnq1ghps5yqc4vkgszlcz92m0000gp/T/tmp.X1tRYLrm/.venv/lib/python3.10/site-packages/click/core.py", line 1404, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/private/var/folders/l0/lnq1ghps5yqc4vkgszlcz92m0000gp/T/tmp.X1tRYLrm/.venv/lib/python3.10/site-packages/click/core.py", line 760, in invoke
    return __callback(*args, **kwargs)
  File "/private/var/folders/l0/lnq1ghps5yqc4vkgszlcz92m0000gp/T/tmp.X1tRYLrm/t.py", line 6, in cli
    raise EOFError('I want to see this exception')
EOFError: I want to see this exception

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/Users/albert/.pyenv/versions/3.10.4/lib/python3.10/runpy.py", line 196, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "/Users/albert/.pyenv/versions/3.10.4/lib/python3.10/runpy.py", line 86, in _run_code
    exec(code, run_globals)
  File "/private/var/folders/l0/lnq1ghps5yqc4vkgszlcz92m0000gp/T/tmp.X1tRYLrm/t.py", line 10, in <module>
    cli.main(standalone_mode=False)
  File "/private/var/folders/l0/lnq1ghps5yqc4vkgszlcz92m0000gp/T/tmp.X1tRYLrm/.venv/lib/python3.10/site-packages/click/core.py", line 1068, in main
    [HIDDEN]
click.exceptions.Abort
```


Environment:

- Python version: 3.10.4
- Click version: 8.1.3

### Additional contract requirements

- When standalone mode is disabled and Click converts an `EOFError` or `KeyboardInterrupt` into `click.exceptions.Abort`, the resulting `Abort` must retain the original exception as its cause (`__cause__`), so the original exception remains visible through exception chaining.
