Simplify cookiecutter.hooks.find_hooks
We should rename `cookiecutter.hooks.find_hooks` to `find_hook(hook_name)` and explicitly look for the requested hook, instead of processing all the files in the hooks directory.

See https://github.com/audreyr/cookiecutter/pull/768/files/9a94484093ca23e9d55d42a53f096f67535b0b63#r68646614
