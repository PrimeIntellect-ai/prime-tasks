GH Poi does not work with multiple github account workaround
**Description**
Bear with me, as this is half way between a bug report and a feature request. I am also willing to help 'fix' this, if given some pointers on where and how.

I like the extension, and would love to use it more, however... If you have used the strategy to handle multiple github accounts (a version of which is [here](https://medium.com/the-andela-way/a-practical-guide-to-managing-multiple-github-accounts-8e7970c8fd46)), you potentially have a non-resolving domain in your remotes somewhere, along the lines of `git@github.com-work:me/blah.git`. The hack in the `.ssh/config` file turns this back into github.com, and everything is good as far as git goes (and the correct identity/ssh key gets used)

However, of course this doesn't work in gh-poi:

```
== DRY RUN ==
✕ Fetching pull requests...
failed to run external command: gh
error connecting to github.com-work
check your internet connection or https://githubstatus.com
```
I'm not entirely sure what I am suggesting here. Something along the lines of: If its an ssh type remote, then check `~/.ssh/config` for a remapping?

I'm not entirely sure. I do know, however, that I am not the only person who uses this method, so thought I would open a conversation on it.

**Additional context**

None that I can think of.

### Additional contract requirements

- Add a public method `GetSshConfig(name string) (string, error)` to the `Connection` interface in package `main` (poi.go), and to the concrete `Connection` type in package `conn` (conn/command.go). It invokes `ssh -T -G <name>` and returns the command's raw output and error.
- When the primary remote's hostname is an SSH alias (for example `github.com-work`), resolve the real hostname from the SSH configuration for that alias (for example `github.com`) and use the resolved hostname for the subsequent GitHub operations.
- If retrieving the SSH configuration fails, continue using the original remote hostname.
