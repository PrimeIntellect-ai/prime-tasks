Bash completion with Positional Arguments
- command: `exports.command = 'test <dir>';`
- exec: `node bin.js --get-yargs-completions`
- output: `test <dir>`
- then the bash completion will output  `test` and `<dir>`

[completion](https://github.com/yargs/yargs/blob/master/lib/completion.js#L59) should be [HIDDEN]

### Additional contract requirements

- Bash command completion must suggest registered command names without emitting positional-argument placeholders as separate candidates.
