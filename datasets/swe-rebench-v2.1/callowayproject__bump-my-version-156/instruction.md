Passing invalid command line arguments does not result in non-zero exit code
* bump-my-version version: 0.19.0
* Python version: 3.9.13 / 3.9.18
* Operating System: Windows 11 Pro 10.0.22631 Build 22631 / Debian Bookworm 12.5

### Description

When invalid argument(s) are passed to the `bump-my-version` tool, it displays the usage message, but then exits with a zero status which can mask the problem in automation jobs relying on command exit code.

### What I Did

```
bump-my-version.exe --foo bump patch && echo Success
```

Results in

```
 Usage: bump-my-version [OPTIONS] COMMAND [ARGS]...

 Version bump your Python project.

╭─ Options ────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ --version      Show the version and exit.                                                                            │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭─ Commands ───────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ bump                   Change the version.                                                                           │
│ replace                Replace the version in files.                                                                 │
│ sample-config          Print a sample configuration file.                                                            │
│ show                   Show current configuration information.                                                       │
│ show-bump              Show the possible versions resulting from the bump subcommand.                                │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

Success
```
