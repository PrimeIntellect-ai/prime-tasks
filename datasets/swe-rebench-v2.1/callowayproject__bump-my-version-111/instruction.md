Single integer version "current_version" incorrectly autocast from str to int on dump/load, causing subsequent bumps to fail with pydantic_core._pydantic_core.ValidationError (Input should be a valid string)
* bump-my-version version: 0.12.0
* Python version: 3.9.18
* Operating System: Linux (Ubuntu 22.04)

### Description

When using a versioning scheme with only a single integer part (e.g. version 1, version 2, etc...) rather than a semantic version (e.g. version 1.2.3), something during a roundtrip of the config file causes subsequent bumps to fail. I'm not sure whether it's a problem with dumping the updated config after a bump, with loading the updated config on the next bump, or a combination of the two.

With this minimal example:

```
[bumpversion]
current_version = "2"
commit = False
tag = False
parse = (?P<major>\d+)
serialize =
	{major}
...
```

After running a command like:

```
$ bump-my-version bump --allow-dirty --config-file .bumpversion.cfg major
```

The updated config file automatically becomes:

```
[bumpversion]
current_version = 3
commit = False
tag = False
parse = (?P<major>\d+)
serialize =
	{major}
...
```

Instead of maintaining the string quotes, it has converted the value for the new `current_version` to an integer instead of a string.

Then on a future bump, you get the following error from Pydantic validation:

```
Traceback (most recent call last):
  File "/home/foo/virtualenv/bar/bin/bump-my-version", line 8, in <module>
    sys.exit(cli())
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/click/core.py", line 1130, in __call__
    return self.main(*args, **kwargs)
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/rich_click/rich_command.py", line 126, in main
    rv = self.invoke(ctx)
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/click/core.py", line 1657, in invoke
    return _process_result(sub_ctx.command.invoke(sub_ctx))
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/click/core.py", line 1404, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/click/core.py", line 760, in invoke
    return __callback(*args, **kwargs)
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/bumpversion/cli.py", line 284, in bump
    config = get_configuration(found_config_file, **overrides)
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/bumpversion/config.py", line 200, in get_configuration
    config = Config(**config_dict)  # type: ignore[arg-type]
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/pydantic_settings/main.py", line 71, in __init__
    super().__init__(
  File "/home/foo/virtualenv/bar/lib/python3.9/site-packages/pydantic/main.py", line 164, in __init__
    __pydantic_self__.__pydantic_validator__.validate_python(data, self_instance=__pydantic_self__)
pydantic_core._pydantic_core.ValidationError: 1 validation error for Config
current_version
  Input should be a valid stsring [type=string_type, input_value=3, input_type=int]
    For further information visit https://errors.pydantic.dev/2.5/v/string_type
```

Apologies I haven't had time to try a TOML config or CLI only, but would assume they're subject to the same sort of validation on load.

### Expected behaviour

Running the bump command shouldn't require any manual edits inbetween runs.

Ideally the config would be written back in the exact same format with string quotes in the output if they were present in the input.

Alternatively, updating the autocast behaviour on load to handle ints as strings which are required by the Pydantic schema.

I'm not sure if it's viable to allow integer types for the `current_version` in the Pydantic schema as well as strings, or if it's just simpler to use strings consistently.

Let me know if I can provide any further information.

Cheers,
Kyle
