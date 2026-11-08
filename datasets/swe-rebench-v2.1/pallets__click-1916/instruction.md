Arguments may break `--help`
Using `click.Path` for an argument may prevent the `--help` from showing up. A simple example is the following:

```
@click.command()
@click.option(
    "-f",
    type=click.Path(exists=True, file_okay=True),
    default="this does not exist",
    help="Output file name",
    show_default=True,
)
def cli():
    pass
```

When trying to print the `--help` the default argument will be checked for validity and instead print an error that `-f` is an invalid value.

Environment:

- Python version: Python 3.8.9
- Click version: 8.0.0
