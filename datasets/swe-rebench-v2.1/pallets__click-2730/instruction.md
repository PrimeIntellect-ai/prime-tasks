Flag option with secondary opts: show_default=True does not show value from default_map in "help" output
I'm setting the `default_map` from a config file, and it seems the values from the `default_map` are not correctly shown in the `--help` output if I set `show_default=True` on my option.

My Option looks like this:

```python
@click.option(
    "--long/--short",
    "-l/-s",
    is_flag=True,
    show_default=True,
    help="show additional information like size and creation date",
)
```

I initialize the `default_map` with a custom command class that I attach via the `@click.command` decorator like this `@click.command(cls=ConfigAwareCommand)`

```python
from click import Command as _Command


class ConfigAwareCommand(_Command):
    def __init__(self, *args, **kwargs):
        kwargs["context_settings"] = {
            "default_map": CONFIG.get_cli_command_defaults(kwargs["name"])
        }
        super().__init__(*args, **kwargs)

```

The `default_map` value is in my example `{'long': True}`. In the `--help` output, the default value is shown like this

```
  -l, --long / -s, --short        show additional information like size and
                                  creation date  [default: short]
```

When executing the command, the default value from the `default_map` is used correctly (`long` defaults to `True`).

During debugging, I might have found the culprit inside [src/click/core.py](https://github.com/pallets/click/blob/main/src/click/core.py#L2746)

```python
            elif self.is_bool_flag and self.secondary_opts:
                # For boolean flags that have distinct True/False opts,
                # use the opt without prefix instead of the value.
                default_string = _split_opt(
                    [HIDDEN]
                )[1]
```

[HIDDEN]

I am not sure if I do something wrong or if this is indeed a bug.

Environment:

- Python version: 3.10.12
- Click version: 8.1.7

### Additional contract requirements

- For a boolean flag with secondary options and `show_default=True`, the help output must display the option corresponding to the effective default, including when that default is provided through `default_map`.
