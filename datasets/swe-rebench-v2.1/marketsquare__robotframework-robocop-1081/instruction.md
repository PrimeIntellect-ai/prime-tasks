[Bug] --ext-rules path in argument file should be relative to the argument file location
### What happened?

Running robocop with `--ext-rules` parameter takes a path relative to the location where the robocop is launched. When using the argument file with `-A` parameter then `--ext-rules` should be relative to the argument file.

### What command/code did you try to run?

robocop tests/ -A tests/roboargs.txt

Argument file has following line:
--ext-rules libraries/robocop/

External rules are located to /tests/libraries/robocop


### What is the full error message?

Error: Fatal error: Failed to load external rules from file "/libraries/robocop/". Verify if the file exists

### What did you expect to happen instead?

Get ext-rules from the relative location to the argument file location.

For example in argument file:
`--ext-rules libraries/robocop/` could point relative to the argument file and `--ext-rules ./libraries/robocop/` could point relative to location robocop is launched.

### Operating System

Linux

### Robocop version

5.0.4
