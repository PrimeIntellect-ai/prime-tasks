[Feature proposal] Single string input without using the `shell`
I can submit a PR for this feature proposal if approved.

I think many users might use `execa.shell()` or the `shell: true` option as a way to pass arguments as a single string which feels more intuitive than using one string + one array:

```js
execa.shell('eslint *.js *.yml --ignore-path=.gitignore --fix --cache --format=codeframe --max-warnings=0')
execa('eslint', ['*.js', '*.yml', '--ignore-path=.gitignore', '--fix', '--cache', '--format=codeframe', '--max-warnings=0'])
```

However those two calls use very different mechanism to execute the command, as the first one relies on system calls and the second one uses a shell interpreter. Using a shell interpreter is:
  - less secure: it allows for [command injection](https://www.owasp.org/index.php/Command_Injection) by passing arguments like `$(rm -rf /)` or `&& rm -rf /`
  - less cross-platform: it encourages using [shell-specific features](https://twitter.com/ehmicky/status/1098980276787732480) such as globbing, single quote escaping or even semicolons which won't work on `cmd.exe`.
  - slower as it goes through an extra step (the shell interpreter)

Using the shell interpreter can almost always be avoided as almost all shell features can be emulated in Node.js:
  - globbing can be done with libraries like `minimatch`. Directory recursion can also be used.
  - piping, subcommands, chaining and streams redirection can be done with the `std*` and `input` options.
  - escaping/quoting becomes unnecessary.
  - variable expansion can be done with template strings. This includes `process.env`.
  - passing environment variables can be done with the `env` option.
  - built-in Bash commands logic can be performed in JavaScript instead.
  - background processes can be done with the `detached` option.

In order to encourage more secure, cross-platform and faster shell execution, I suggest the following:
  - when the `shell` option is `false`, the first argument can be either `command` (current behavior) or `command ...args` (new behavior)
  - `command ...args` is a string delimited by spaces.
  - spaces can be escaped with backslashes: `command escaped\ space`. Anything else does not need escaping, just like the `args` array.

What do you think? Again if approved I can submit a PR.
