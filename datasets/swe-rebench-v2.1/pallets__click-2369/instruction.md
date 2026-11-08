Spurious empty lines in the help output (regression)
Click since version 8.1.0 doesn't properly account for a scenario that the callback's docstring can have no "help text" part, like so:

```python
@click.command()
def callback():
    """
    \f
    More stuff.
    """
```
This results in empty lines in the output:

```
% python3 test --help
Usage: test [OPTIONS]



Options:
  --help  Show this message and exit.
```

Before 8.1.0:
```
% python3 test --help
Usage: test [OPTIONS]

Options:
  --help  Show this message and exit.
```

Environment:

- Python version: 3.9.2
- Click version: 8.1.3
