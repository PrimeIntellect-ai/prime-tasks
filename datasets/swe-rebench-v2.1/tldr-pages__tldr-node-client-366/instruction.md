tldr fails silently when trying to read invalid `.tldrrc` leading to confusion
I come from here: https://github.com/tldr-pages/tldr/issues/1262

https://github.com/tldr-pages/tldr-node-client/blob/1641dea94df3aabcd36f381dcac61a50905a36ea/lib/config.js#L16-L21

There should be some error printed on error stream that the JSON object couldn't be loaded due to invalid syntax. JSON parse fails silently when the file is missing (that's OK), but SHOULD error when the config is invalid. Common examples when `*rc` files print errors include `.vimrc`, `.tmux.conf` and probably others.

The simplest case - yeet the ESlint directives and add proper error handling.

### Additional contract requirements

- `config.get()` must throw an `Error` when the custom configuration file `.tldrrc` exists but does not contain valid JSON. The thrown error's message must contain the text `not a valid JSON object`.
- When the custom configuration file `.tldrrc` is missing (for example, `fs.readFileSync` fails with an `ENOENT` error), `config.get()` must not throw and must return the default configuration.
