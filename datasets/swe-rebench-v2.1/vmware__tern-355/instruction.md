Add a version argument to tern CLI
**Describe the Feature**
Currently there is no way to identify the version of tern installed.  Typically a CLI will have a `--version` argument to provide such information.

As a added bonus, it's good to put environmental information in the version output that way you can tell people to simply run a command and copy the output into a bug being reported.

**Use Cases**
This would be very helpful for those opening bugs and need to provide version and environment information.

**Implementation Changes**
Describe what changes you think would need to happen to the code to implement this feature
```
pseudocode or python code is fine here
```

### Additional contract requirements

- Running the Tern command-line tool with `--version` prints the installed Tern version (for example `Tern 0.4.0`) and exits successfully without running a subcommand.
- The version output also includes the Python version in use, so users can paste it into bug reports.
