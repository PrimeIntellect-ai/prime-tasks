Allow `params` attribute in decorators
Currently it is not possible to pass `params` attribute to `@command()` and `@group()` decorators.
This would be really simple implementation, which can be seen in [this forked commit](https://github.com/kristianheljas/click/commit/4e908df69ab11eb333fa14bcf4f3b54b77810ef4)

Although, this allows to mix decorator and class patterns, there are a few advantages as well:

1. Share same option spec between (sub)commands (consider CRUD subcommands which all have `--force` option, except `read`)
It can be done with nested decorators, which hurt readability
2. Take advantage of IDE auto-completion when using `Option()` class instead of decorator ([PEP-612](https://www.python.org/dev/peps/pep-0612/) would resolve this, but it requires python >=3.10)

If this is something to be considered, I can follow up with a PR.

Example usage:

```python
import click

@click.group()
def crud():
    ...

write_args = [
    click.Option(['--force'], is_flag=True)
]

@crud.command(params=write_args)
def create():
    ...

@crud.command(params=write_args)
@click.option('--create', is_flag=True) # Should this be appended or prepended to `write_args`?
def update():
    ...

@crud.command(params=write_args)
def delete():
    ...

@crud.command()
def read():
    ...
```

### Additional contract requirements

- Both `@click.command(params=...)` and `@click.group(params=...)` accept the
  `params` keyword and populate the resulting command's `params` list with the
  supplied parameters.
- Parameters added by later decorator helpers (`@click.option`,
  `@click.argument`, etc.) are appended after the supplied `params`, in the
  order the decorators are declared.
