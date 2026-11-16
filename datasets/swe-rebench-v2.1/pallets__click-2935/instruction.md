Completion for commands in nested groups is broken in Click 8.2.0
## Summary

In Click 8.2.0, completion for commands in nested groups doesn't work as expected anymore. Instead of completing command options and/or arguments, completion infinitely repeats the command names for the group.

## Example program

Inspired by the example in #2847

Save the following as `bin/nested` in a virtualenv

```python
#!/usr/bin/env python

# nested

import click


def _complete_arg(ctx, _, incomplete):
    values = [
        "foo",
        "bar",
        "foobar",
        "baz",
    ]
    return [v for v in values if v.startswith(incomplete)]

@click.group
def main():
    ...

@main.group
def subgroup():
    ...

@subgroup.command
@click.option("--name", help="Name of something.")
@click.argument("arg", shell_complete=_complete_arg)
def compile(name: str | None, arg: str) -> None:
    """Test argument completion in nested groups."""
    click.echo(f"{name=} {arg=}")


if __name__ == "__main__":
    main.main()
```

Run `eval "$(_NESTED_COMPLETE=bash_source nested)"` to setup completion (for bash)

## Completion behavior

|Prefix|8.2.0 completion suggestions (unexpected behavior)|8.1.8 completion suggestions (expected behavior)|
|-|-|-|
|`nested`|`subgroup`|`subgroup`|
|`nested subgroup`|`compile`|`compile`|
|`nested subgroup compile`|`compile`|`foo     bar     foobar  baz`|
|`nested subgroup compile f`|none|`foo     foobar`|
|`nested subgroup compile --`|`--help`|`--name  --help`|
|`nested subgroup compile --name=n`|`compile`|`foo     bar     foobar  baz`|

## Environment

- Python version: Python 3.12.3
- Click version: 8.2.0

## Initial debugging

Reverting 0ef55fda47bb3d0dece21197d81d8d72a4250e73 for `src/click/shell_completion.py` restores the 8.1.8 completion behavior.

[HIDDEN]

Note that Click 8.1.8 directly assigns `cmd.make_context()` to `ctx` in the equivalent snippet: https://github.com/pallets/click/blob/934813e4d421071a1b3db3973c02fe2721359a6e/src/click/shell_completion.py#L530-L531

[HIDDEN]
