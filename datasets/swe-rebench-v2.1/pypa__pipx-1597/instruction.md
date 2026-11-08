No output from `pipx upgrade-all` when no packages have upgrades
**Describe the bug**

Before (in 1.4.x?), `pipx upgrade-all` used to print a message that said `No packages upgraded after running 'pipx upgrade-all'`.  After upgrading to 1.6.0 the message is gone, and `upgrade-all` produces no output (there is some output while it tries to upgrade the installed packages, but no output remains after the command is executed).

I'm not sure if this was an intentional change or a bug.  The code was recently changed in c9d31a6 (#1357 by @huxuan) and the message is still there:

https://github.com/pypa/pipx/blob/99c998dc3b798559ebf602fdbe8bb5a24f1c98dd/src/pipx/commands/upgrade.py#L264-L265

however I don't see it in the output, even while using `-v` (I see several other lines of output though).

**How to reproduce**

Make sure that all packages are upgraded, then run `pipx upgrade-all`.

**Expected behavior**

I would like to see a message stating that currently no package needs upgrades.

### Additional contract requirements

- When no packages need upgrades, `pipx upgrade-all` must print `No packages upgraded after running 'pipx upgrade-all'`.
