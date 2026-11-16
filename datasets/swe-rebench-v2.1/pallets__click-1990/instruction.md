`required=True` does not work for flags
When using a flag option, setting `required=True` has no effect unless I also include `default=None`. I would expect there to be no default if the flag is required.


**Steps to reproduce:**
```
import click

@click.command()
@click.option('--foo/--no_foo', is_flag=True, required=True)
def bar(foo):
    pass

if __name__ == '__main__':
    bar()

```

`python test.py` runs without raising an error.

I would expect `python test.py` to raise:
```
Usage: test.py [OPTIONS]
Try 'test.py --help' for help.

Error: Missing option '--foo'.
```

Environment:

- Python version: 3.9.5
- Click version: 8.0.1
