Empty default value in --help output for option with multiple=True
## Minimal reproducible example that demonstrates the bug

```python
#!/usr/bin/env python3

import click

@click.command()
@click.option('--multioption', multiple=True, default=None, help='My help', show_default=True)
def info(_multioption):
    pass


if __name__ == '__main__':
    info()
```

Notice `multiple=True` which is crucial. If you replace it with `multiple=False` it will work just fine.

### What I get

```console
$ ./test.py --help
Usage: test.py [OPTIONS]

Options:
  --multioption TEXT  My help  [default: ]
  --help              Show this message and exit.  [default: False]
```

### Expected output

```console
$ ./test.py --help
Usage: test.py [OPTIONS]

Options:
  --multioption TEXT  My help
  --help              Show this message and exit.  [default: False]
```

## Environment

### Python version

```console
$ python3 --version
Python 3.9.2
```

### Click version

```console
$ python -c "import click; print(click.__version__)"
8.0.1
```
(I checked that `8.0.2.dev0` is also affected)
