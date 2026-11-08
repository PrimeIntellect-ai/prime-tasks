Easily replace only the messages for --help and --version
I'm trying to help make a project's help messages consistent, and all of the messages are of the format "Start …", "Check …", "Print …", so the "Prints  version information" stands out. I was unable to find an easy way to replace only the help and version messages without re-wiring the commands themselves. Is there any easy solution I missed, or is this something that would have to be added.

### Additional contract requirements

- `App::help_message` must allow the description shown for the automatically generated help option to be replaced, without requiring the caller to define or rewire that option.
- `App::version_message` must allow the description shown for the automatically generated version option to be replaced, without requiring the caller to define or rewire that option.
