argument with nargs=-1 and envvar ignores values from command line
Since click 8.0, the value(s) provided on the command line for a nargs=-1 argument are ignored if the argument has `envvar` set.

Example:

```python
#!/usr/bin/env python
import click

@click.command()
@click.argument("foo", nargs=-1, envvar="FOO")
def cli(foo):
    click.echo(foo)

if __name__ == "__main__":
    cli()
```

```
$ ./clickbug arg1 arg2
()
```


When arguments are passed on the command line, the `foo` value remains empty. Removing the `envvar` option makes it work again. Values from the environment variable are picked up, though. Reverting to `click<8` also fixes the problem.

The cause of the bug is possibly [here](https://github.com/pallets/click/commit/3d3ea9c64420fd8978a41ce8b4db3ac2d245849c#diff-948f9e0cc733616a6b18aa152ac6703e819fec61dd752d1efa40e5736c3bdce7): [HIDDEN]

Environment:

- Python version: 3.8.5
- Click version: 8.0.0

### Additional contract requirements

- For an argument with `nargs=-1` and an `envvar` configured, non-empty values supplied on the command line must not be discarded.
