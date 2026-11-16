Set environment variable when running commands
### How would this feature be useful?

Setting an environment variable in the environment of `session.run`'d commands would allow the child process to know it is being executed by nox and perhaps even what session of nox is being. Personally, I would find this useful when `session.run`ing `bash` or `code` (using nox as a development environment manager) so that I can adjust my PS1 with the name of the session I'm in.

### Describe the solution you'd like

When running any command with `session.run`, the command environment is adjusted to set the `NOX_CURRENT_SESSION` variable with the name of the current session.

### Describe alternatives you've considered

It's entirely possible to do this myself using `env` argument to `session.run`. However it is something innocuous that takes the burden off the user without considerable maintenance effort.

### Anything else?

_No response_
