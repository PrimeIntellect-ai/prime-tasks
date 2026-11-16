Cannot use parameterless command decorator with custom command_class

Click throws an assertion error if you try to use the parameterless command decorator on a group with a command_class defined. [HIDDEN]


# minimal repro
```
import click

class CustomCommand(click.Command):
    pass

class CustomGroup(click.Group):
    command_class = CustomCommand

@click.group(cls=CustomGroup)
def grp():
    pass

@grp.command
def cli():
    click.echo("hello custom command class")
```
## error

```
ewilliamson@ip-192-168-50-39 ~ % python minimal_repro.py
Traceback (most recent call last):
  File "/Users/ewilliamson/minimal_repro.py", line 14, in <module>
    def cli():
  File "/Users/ewilliamson/.pyenv/versions/3.10.7/lib/python3.10/site-packages/click/core.py", line 1847, in command
    assert (
AssertionError: Use 'command(**kwargs)(callable)' to provide arguments.
```

## expected
The `@grp.command` would be successfully parsed the same as without using `CustomGroup`

<!--
Describe the expected behavior that should have happened but didn't.
-->

Environment:

- Python version: `Python 3.10.7`
- Click version: `click==8.1.3`
