wrong exit code when child process is terminated by a signal
relevant test (added in  #111)

https://github.com/memorysafety/sudo-rs/blob/a536a64d75df5dd90f4d90d8a18a59bcf9d1e2f8/test-framework/sudo-compliance-tests/src/child_process/signal_handling/mod.rs#L57-L66

the original sudo exits with code 143 -- the same code `sh -c 'kill $$'` exits with. sudo-rs exits with code 1 in this case

cc @pvdrz

### Additional contract requirements

- When the executed command is terminated by a signal, the exit status observed
  by the caller must be the conventional shell status `128 + signal number`. For a
  command that terminates itself with SIGTERM (`sh -c 'kill $$'`) that status is
  `143`.
