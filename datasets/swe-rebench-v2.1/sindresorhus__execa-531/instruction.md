Piping shortcut notation
## Problem

Redirecting a process's output to two different targets is a common pattern. For example, a user might want to `inherit` stdout/stderr for debugging reasons, while still using `pipe` to get a process's return value.

This is currently possible, but requires 3 statements, which trips up users who are less familiar with process execution. This required us to explicitly add those in our [Tips documentation](https://github.com/sindresorhus/execa#save-and-pipe-output-from-a-child-process).

```js
const subprocess = execa('echo', ['foo']);
subprocess.stdout.pipe(process.stdout);
const {stdout} = await subprocess;
```

This also makes chaining processes rather verbose. For example, we just got an issue #521 which was mostly related to that problem. The solution is not as simple as it could be.

```js
const ffmpegProcess = execa('ffmpeg', ['-ss', '5', '-i', 'input.mp4', '-t', '1', '-vf', 'cropdetect', '-f', 'null', '-'])
const awkProcess = execa('awk', ['/crop/ {print $NF}'])
const tailProcess = execa('tail', ['-1'])

ffmpegProcess.stderr.pipe(awkProcess.stdin)
awkProcess.stdout.pipe(tailProcess.stdin)

const { stdout } = await tailProcess
```

Having a simple syntax for chaining processes is especially important with the new `$` API because users might expect the convenience of the `|` shell syntax. For example, `zx` provides 2 ways of doing this:

```js
await $`cat package.json | grep name`
```

```js
await $`cat package.json`.pipe($`grep name`)
```

## Solution

This problem could be solved by introducing a shortcut notation. For example, the above examples above could be written as:

```js
const {stdout} = await execa('echo', ['foo']).pipeStdout(process.stdout);
```

```js
const {stdout} = await execa('ffmpeg', ['-ss', '5', '-i', 'input.mp4', '-t', '1', '-vf', 'cropdetect', '-f', 'null', '-'])
  .pipeStdout(execa('awk', ['/crop/ {print $NF}']))
  .pipeStdout(execa('tail', ['-1']))
```

```js
await $`cat package.json`.pipeStdout($`grep name`)
```

It would do the same thing, just in a shorter way, so it would be rather minimal to implement and document.

### Return value

When piping to a stream (like `process.stdout`), the return value would be the `childProcessResult`, not the stream, since users would most likely want to retrieve the process's result.

However, when piping to another `childProcessResult` (i.e. to its `stdin`), that other `childProcessResult` would be returned. This allows command chaining. Also, this mimics how piping works in shells. For example, in Bash, `$(cat package.json | grep name)` returns the result after `grep` has been applied. Overall, this is what users would expect.

### Stderr

`pipeStderr()` and `pipeAll()` could be available to redirect stderr, or stdout+stderr.

### Synchronous methods

Those methods only make sense with the async `execa()` methods, since they would otherwise be called once the process has already completed.

### Alternative solution

We could also implement this using the new `$` API with a special pipe symbol, like `zx` does.

```js
await $`cat package.json | grep name`
```

However, I think this solution might not be as good for the following reasons:
  - It does not work with normal `execa()` and `execaCommand()` calls
  - It introduces special tokens to the ``$`...` `` syntax. At the moment, the string argument only has command and arguments, with no shell-like syntax, which is much simpler to document and understand. It would also create some confusion for users expecting the command to be run in a shell by default (which is not the case) due to the usage of the pipe symbol.
  - It does not work well with functional utilities. For example, `pipeStdout()` can use `.bind()` or be assigned to a variable or parameter. Using a string makes this kind of manipulation harder.
  - It would require 3 different tokens to redirect to stdout, stderr or both.
  - Pipe characters would need a way to be escaped.

### Naming

If you have other naming ideas for `pipeStdout()`, `pipeStderr()` and `pipeAll()`, please let me know!
  - `stdout()`, etc. does not work because `childProcess.stdout` is already assigned as a stream
  - `stdoutTo()`, etc. could work, but users might understand the work "pipe" better
  - `pipe()` could work for `pipeStdout()`, but users might not understand it is a different method than `Stream.prototype.pipe()`.

---

What do you think @sindresorhus?

### Additional contract requirements

- The three methods are named `pipeStdout(target)`, `pipeStderr(target)` and `pipeAll(target)`. They are available on the async execa child process returned by `execa()` and by the `$` tagged template, and each returns an execa child process so the returned value can be chained or awaited.
- `pipeStdout()` is only available when the `stdout` option is `'pipe'` (its default). `pipeStderr()` is only available when the `stderr` option is `'pipe'` (its default). `pipeAll()` is only available when the `stdout` option or the `stderr` option is `'pipe'`.
- The methods are available on the execa child process itself, not on the awaited result.
- When the target is not a file path string, a writable stream, or an execa child process, the thrown error message contains `a stream or an Execa child process`.
- When the target is an execa child process whose `stdin` is not writable, the thrown error message contains `stdin must be available`.
