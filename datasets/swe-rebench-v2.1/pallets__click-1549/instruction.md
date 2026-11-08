show_default and default_map don't play nice together
```python
#!/usr/bin/env python
import click

@click.command(context_settings={
    "show_default": True, "default_map": {"a": "b"}
})
@click.option("-a", default="c")
def func(a):
    print(a)

if __name__ == "__main__":
    func()
```
```console
$ # This is expected
$ ./cli.py
b
$ # This is not (default should be b)
$ ./cli.py --help
Usage: cli.py [OPTIONS]

Options:
  -a TEXT  [default: c]
  --help   Show this message and exit.  [default: False]
```

### Expected Behavior

I expect the default shown to be identical to the one being used.

### Actual Behavior

The default shown was the value provided as `default`, without taking the `default_map` into account

### Environment

* Python version: 3.7
* Click version: ``click==7.1.2``
