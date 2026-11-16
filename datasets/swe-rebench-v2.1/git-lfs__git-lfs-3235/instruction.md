Support core.sshCommand in gitconfig
I have issues with SSH on my corp machine + sourcetree's environment config.

By configuring the git config and setting the sshCommand I can fix this, unfortunately this setting doesn't isn't read by git-lfs

Currently having to do an ugly wrap around git-lfs to get this working

### Additional contract requirements

- Git LFS reads the Git configuration value `core.sshcommand` and uses it as the SSH command for LFS SSH operations. When the `GIT_SSH_COMMAND` environment variable is set, it takes precedence over `core.sshcommand`.
- In package `lfsapi`, `sshGetExeAndArgs(osEnv config.Environment, gitEnv config.Environment, e Endpoint) (exe string, baseargs []string, needShell bool)` selects the SSH executable and base arguments from the OS environment and the Git configuration environment, and reports whether the arguments must be run through a shell.
- In package `lfsapi`, `sshGetLFSExeAndArgs(osEnv config.Environment, gitEnv config.Environment, e Endpoint, method string) (exe string, args []string)` builds the SSH command line for the LFS helper from both environments and appends the LFS authentication command for the operation selected by `method`.
