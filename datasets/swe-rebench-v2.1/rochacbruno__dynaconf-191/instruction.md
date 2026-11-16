Missing an isolated namespace [RFC]
**Is your feature request related to a problem? Please describe.**
A clear and concise description of what the problem is. Ex. I'm always frustrated when [...]

The Settings object should have a way of accessing and traversing the keys loaded from the settings files without having all of the Dynaconf options in there. When I call `config.keys()` I'm getting `['SETTINGS_MODULE', 'PROJECT_ROOT_FOR_DYNACONF', 'SETTINGS_MODULE_FOR_DYNACONF', ...`

**Describe the solution you'd like**
A clear and concise description of what you want to happen.

Ideally when you call `keys()` and similar methods, it should only return values in the namespaces loaded by the file. Even if it involved doing this `config.current_env.keys()` it would be fine.

Also, having methods of exporting the current (possibly modified) settings would be nice. Basically I would like to be able to do this:

```python
with open(output_file, 'w') as f:
    yaml.dump(config.environments['development'].as_dict(), f)
```

And have that write out a flattened version of the development namespace.

**Describe alternatives you've considered**
A clear and concise description of any alternative solutions or features you've considered.

**Additional context**
Add any other context or screenshots about the feature request here.

### Additional contract requirements

- The settings object's `as_dict()` method returns a flat dictionary of the user-defined settings-file values for the current environment, keyed by setting name. It does not include Dynaconf option values such as `SETTINGS_MODULE`, `PROJECT_ROOT_FOR_DYNACONF` or `SETTINGS_MODULE_FOR_DYNACONF`.
- `as_dict(env="production")` returns the same kind of flat dictionary for the named environment, e.g. `name` is `"prod"` there while the default environment keeps its own value.
- The dictionary reflects the current values, including changes made at runtime with `set()`: after `settings.set("NAME", "changed")`, `settings.as_dict()["NAME"]` is `"changed"`.
