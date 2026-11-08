Get color code `just` will use for echoed recipe commands?
Sometimes in shebang recipes it is useful to be able to echo some individual commands before running, the same as `just` echoes commands during a non-shebang recipe.  Prior to https://github.com/casey/just/pull/1670 , simply using bold color when echoing those commands would do the job.  Now, it's no longer known in advance how echoed commands would look.

Could a `just` function to help this please be added?

Perhaps it could wrap a string in color codes same as `just` would wrap an echoed recipe line?  Or, alternatively, perhaps it could take no arguments and return the color code `just` would use for echoing recipe lines?

Thanks :slightly_smiling_face:

### Additional contract requirements

- A recipe can call the built-in function `style` with the argument `"command"` to obtain the terminal escape sequence that `just` uses when it echoes recipe command lines. Interpolating it before text and following the text with `{{NORMAL}}` should style that text the same way `just` styles its echoed commands.
- The returned sequence reflects the `--command-color` option: with the default settings it is bold, and with `--command-color red` it is bold red.
