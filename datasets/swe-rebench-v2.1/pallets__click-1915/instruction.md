Click 8.0.0 `group.add_command(..)` does not replace name in description and when looking up defaults
With click 8.0.0 `click.group.add_command(..)` changed the behavior in how new command names are used:
Both the help text for the command as well as when looking up default values in `default_map` the previous command name instead of the one added by the group are shown.

Minimal example:

```
# test.py
import click

@click.command()
@click.option(
    "--qux",
    required=True
)
def foo(qux):
    print(qux)

@click.group()
def group():
    pass

group.add_command(foo, "bar")

group(default_map={"bar": {"qux": "val"}})
```
Run the above:
* with click 7.x:
> $ python3 test.py bar --help
> Usage: test.py bar [OPTIONS]
> // and
> $ python3 test.py bar
> val
* with click 8.0.0:
> $ python3 test.py bar --help
> Usage: test.py foo [OPTIONS]
> // and
> $ python3 test.py bar
> Usage: test.py foo [OPTIONS]
> Try 'test.py foo --help' for help.
>
> Error: Missing option '--qux'.

I would have expected that both the help shows the name of the command as "bar" (as using "foo" will result in an error)
and the lookup for the default using "bar" as a key.

Environment:

- Python version: 3.9.5
- Click version: 8.0.0
