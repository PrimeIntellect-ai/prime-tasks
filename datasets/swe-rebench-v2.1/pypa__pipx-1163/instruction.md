Option for the `list` command not to go out to the internet
**How would this feature be useful?**

When using pipx while the system has no internet connection, `pipx list` takes an awful long time because before printing teh list of packages it tries to upgrade the shared libraries.

**Describe the solution you'd like**

The main purpose of the `list` command is to list what's there, so if I know I have no internet I should be able to say "_Just give me the list. I don't care about doing other maintenance things._" because these maintenance things won't work in any case.

**Describe the solution you'd like**
An option like `--no-maintenance` or `--dont-update` for the `list` command.

### Additional contract requirements

- The `list` command accepts a `--skip-maintenance` flag.
