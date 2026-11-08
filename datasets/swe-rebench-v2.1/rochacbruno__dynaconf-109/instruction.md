[RFC] Allow dynaconf cli to use a customized settings object
I have a customized settings object:

```python
from dynaconf import LazySettings

settings = LazySettings(
    GLOBAL_ENV_FOR_DYNACONF='MYPROJECT',
    MERGE_ENABLED_FOR_DYNACONF=True,
)
```

When I run `dynaconf` cli tool, it knows nothing about my customization. How can I tell `dynaconf` cli tool to use my customized version of settings?

### Additional contract requirements

- The `dynaconf` command line tool must be able to operate on a user-provided customized settings object instead of its default settings.
- The object is selected by a dotted Python path to the `LazySettings` instance (for example `myapp.settings`), passed with the `--instance` (or `-i`) command line option placed before the command name, e.g. `dynaconf -i myapp.settings list`.
- The same selection can be made with the `INSTANCE_FOR_DYNACONF` environment variable set to that dotted path, e.g. `INSTANCE_FOR_DYNACONF=myapp.settings dynaconf list`.
- When a custom instance is selected this way, commands such as `list` show the values held by that object (for example, a value set in its constructor appears in the `list` output).
