Shell completion does't parse escaped slashes or spaces correctly
When a value with an escape string, for instance `my\ file`, is passed to a `click.ParamType`, the `incomplete` value which is passed to `click.ParamType.shell_complete` will only be `"my\ "` instead of `my file`.

### Expected Behavior

```python
import click

@click.command()
@click.argument("name", type=click.Choice(["my file", "my folder", "my\\ file", "other"]))
def cli(name):
    click.echo(name)

if __name__ == '__main__':
    cli()
```

Completing `my\ f` should be interpreted as the Python string `"my f"` and match the first two values.

```
$ example my\ f<TAB>
my\ file
my\ folder
```

### Actual Behavior

Completing `my\ f` is interpreted as the string `"my\\ f"` and matches the third value.

```shell
$ example my\ f<TAB>
my\\\ file
```

### Environment

* Python version: 3.8.6
* Click version: 8.0.0.dev0

### Additional contract requirements

Add a public function `split_arg_string(string)` in module `click.parser`. It
splits a command line string in a shlex-like manner and returns a list of
string tokens. It must tolerate incomplete quoting or escape sequences without raising,
returning the partial token. An incomplete trailing escape may be retained or
discarded.
