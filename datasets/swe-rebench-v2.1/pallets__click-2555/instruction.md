Error in click.utils.echo() when console is unavailable
The `click.utils.echo()` function does not seem to account for the case when the console is not available on Windows, i.e., when running under `pythonw.exe` interpreter instead of the `python.exe` one.

Minimal example:

```python
# program.py
import sys
import os

try:
    import click
    click.utils.echo("Hello world")
except Exception:
    import traceback
    error_file = os.path.join(os.path.dirname(__file__), "error_log.txt")
    with open(error_file, "w") as fp:
        traceback.print_exc(file=fp)
```

Running this program with `pythonw.exe program.py` produces the `error_log.txt`:
```
Traceback (most recent call last):
  File "C:\Users\Rok\Development\pyi-click\program.py", line 6, in <module>
    click.utils.echo("Hello world")
  File "C:\Users\Rok\Development\pyi-click\venv\lib\site-packages\click\utils.py", line 299, in echo
    file.write(out)  # type: ignore
AttributeError: 'NoneType' object has no attribute 'write'
```

In contrast, standard `print()` function gracefully handles situations when console is unavailable and `sys.stdout` and `sys.stderr` are `None`.

[HIDDEN]

Environment:

- OS: Windows
- Python version: any
- Click version: 8.1.3 (and earlier)

### Additional contract requirements

- When `click.utils.echo()` selects a standard output or error stream that is `None`, it must return without raising an exception or producing output.
