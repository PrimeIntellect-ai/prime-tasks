show envvar in error hint
```py
@click.command()
@click.option('--a', required=True, envvar="b", show_envvar=True)
def f(a): ...
f()
```
Here I would want the error message to show the env var.

### Additional contract requirements

- For a required option declared as `--foo` with `envvar="bar"` and `show_envvar=True`, the missing-option error must be `Error: Missing option '--foo' (env var: 'bar').`
