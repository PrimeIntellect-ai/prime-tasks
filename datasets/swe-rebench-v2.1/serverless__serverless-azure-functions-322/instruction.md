Error: spawn func.cmd ENOENT
If `azure-functions-core-tools` is not installed globally, spawning of process fails.

Current thought is to run `npx` as the command instead of func. Or to just run the executable within `node_modules/.bin`

### Additional contract requirements

- For offline startup, when using `npx`, the command must be exactly `npx`; its arguments may include options before `func` or `func.cmd`, which must be followed by exactly `host`, `start`. Alternatively, invoke the local executable under `node_modules/.bin` (`func` on non-Windows and `func.cmd` on Windows) with exactly `host`, `start` as arguments.
