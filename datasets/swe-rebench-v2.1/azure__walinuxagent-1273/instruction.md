Agent Prematurely Terminates Long Running Extensions
A user opened an issue against [Azure/custom-script-extension-linux #139](https://github.com/Azure/custom-script-extension-linux/issues/139) about the extension prematurely timing out.  I have verified this issue against 2.2.29.

```sh
az vm extension set -g my-resource-group --vm-name vm1 --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.0 --settings "{ \"commandToExecute\": \"sleep 360; ls\" }"
```

The agent will kill the process after five minutes, which is different from previous behavior.  The logs for the agent claim that it moved the extension PID into a cGroup, but the PID it referenced in the logs is the PID *agent ext-handler process* not the extension.

### Additional contract requirements

- For a forked command whose output cannot be collected, `capture_from_process` must return exactly `[stdout]\ncannot collect stdout\n\n[stderr]\n`.
- When a non-forked process exceeds a 10-second timeout, `capture_from_process` must raise `ExtensionError` with a message containing `Timeout(10)`.
- When `capture_from_process` handles a forked command whose output cannot be collected, it must return in less than 3 seconds, even when the supplied timeout is 10 or 20 seconds.
- For a non-forked process that completes within its timeout, `capture_from_process` must return output containing `Iteration 9` and `Iteration 10`.
- When `launch_command` runs a long-running extension that forks with `timeout=10`, it must return in less than 5 seconds without terminating the forked child process.
