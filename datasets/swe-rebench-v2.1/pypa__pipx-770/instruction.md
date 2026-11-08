Upgrading shared libraries messes up JSON output
**Describe the bug**
I have a script that parses the output of `pipx list --json` to list all installed packages. Today, it triggered the upgrading shared libraries logic. The upgrader wrote "upgrading shared libraries..." to stdout, which caused an error when attempting to parse the JSON output.

**How to reproduce**
Manually set `SHARED_LIBS_MAX_AGE_SEC = 0`. Then run `pipx list --json`.

**Expected behavior**
Stdout should contain valid JSON. Instead it contains `upgrading shared libraries...\n{ JSON output... }`

### Additional contract requirements

- When animation is disabled or unavailable, emit the progress message followed by `...` and a newline on stderr, and emit nothing on stdout.
