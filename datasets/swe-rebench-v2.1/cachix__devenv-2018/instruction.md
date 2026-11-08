tasks namespace detection doesn't work with sub-namespaces.
## Bug description

#1877 introduced running tasks by namespace:

`devenv tasks run "ci"` run:

- ci:format:nixfmt
- ci:format:shfmt
- ci:lint:shellcheck

but `devenv tasks run "ci:format"` does nothing.

## To reproduce

```nix
tasks = {
  "ci:format:nixfmt".exec = "echo '["nixfmt"]' > $DEVENV_TASK_OUTPUT_FILE'';
  "ci:format:shfmt".exec = "echo '["shfmt"]' > $DEVENV_TASK_OUTPUT_FILE'';
  "ci:lint:shellcheck".exec = "echo '["shellcheck"]' > $DEVENV_TASK_OUTPUT_FILE'';
};
```

## Version

devenv 1.7.0 (x86_64-linux)
