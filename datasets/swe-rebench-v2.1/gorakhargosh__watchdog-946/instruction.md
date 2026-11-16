watchmedo auto-restart behavior change with 2.1.9
We were using `watchmedo auto-restart` to call mypy and some flake8 tooling upon file changes. With the changes introduced by https://github.com/gorakhargosh/watchdog/pull/896, these processes re-run continually every time they exit whereas before they were re-ran upon a watched file/directory change.

The name `auto-restart` makes me believe that this is actually desirable behavior and perhaps we were misusing that sub-command, however there doesn't appear to be an alternative to get the behavior we once had. `watchmedo shell-command` only runs the command on change with no option to run it once _and also_ upon watched file change.

Is there a way to add a flag to `auto-restart` which only restarts on an exit code, or maybe a way to use `shell-command` to call the command initially and then repeat on a file change?

### Additional contract requirements

The `watchmedo auto-restart` command must provide a `--no-restart-on-command-exit` flag. Without this flag, the command must retain the existing behavior of restarting when its managed process exits. With the flag, it must start the command initially and must not restart it merely because it exits; a later change to a watched file or directory must still cause the command to run again.
