[Feature proposal] Improved error messages
The current code has [some logic](https://github.com/sindresorhus/execa/blob/master/index.js#L155) aimed at providing better error messages. It would be nice to add the following error messages:
  - `Command timed out after 5 seconds: ...` if `timedOut` is `true`.
  - `Command was killed with SIGTERM` if `signal` is not `null`.
  - `Command failed with exit code 2 (ENOENT)` otherwise.

The values (e.g. `SIGTERM`) in the messages above are for example purpose.

I can provide with a PR if this feature proposal is approved.

### Additional contract requirements

- The improved message keeps the original error message (the command and any captured output) after the prefix, separated by a colon. For example, a command that exits with code 2 produces a message of the form `Command failed with exit code 2 (ENOENT): <original message>`.
