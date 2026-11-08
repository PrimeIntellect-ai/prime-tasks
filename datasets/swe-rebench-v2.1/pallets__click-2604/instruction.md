strip "_command" suffix when generating command name
You often want a command to have the same name as a function it is wrapping. However, this will cause a name collision, if your command is going to call `init_data` its function can't also be called `init_data`. So instead it's written as `init_data_command`, and then the command name has to be specified manually `@command("init-data")`. Click should remove a `_command` suffix when generating the command name from the function name.

```python
def init_data(external=False):
    ...

@cli.command
@click.option("--external/--internal")
def init_data_command(external):
    init_data(external=external)

```

Currently this command would be named `init-data-command`. After the change, it would be `init-data`.
