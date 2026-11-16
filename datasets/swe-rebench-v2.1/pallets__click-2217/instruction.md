group return value is ignored
Calling a command defined as `@click.group()` with `standalone_mode=False` does not propagate the return value as expected.

For instance:
```python
import click
import sys

@click.group(invoke_without_command=True)
@click.option("-l", "--local-configuration", type=str)
def main(local_configuration):
    print('Inside main')
    return 1

if __name__ == '__main__':
    print(main(sys.argv[1:], standalone_mode=False))
```

```
$ python test.py
Inside main
None
```

It does work when the command is defined with `@click.command()`, hence I suppose this is a bug.

Environment:

- Python version: 3.7.5
- Click version: 8.0.3

### Additional contract requirements

- A group's result callback, registered with the `@cli.result_callback()`
  decorator, is invoked when the group is defined with
  `invoke_without_command=True` and is invoked without a subcommand. For a
  regular (non-chained) group the callback receives the group function's
  return value; for a chained group it receives an empty list (`[]`).
