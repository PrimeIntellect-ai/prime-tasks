Allow using custom close function / command
So as you might already know, the default `:bdelete` command in Neovim is quite annoying in the sense that it messed up the window layouts. I made a function that bypasses it and would want to be able to configure nvim-bufferline to use it instead of `:bdelete` or whatever else it uses for deleting that buffer. So it would be really nice to have that option.

### Additional contract requirements

Closing a buffer can use the `close_command` option instead of the default deletion action. The option accepts either a Lua function, which receives the buffer number being closed, or a command string, in which `%d` is replaced with that buffer number before the command runs. When no custom `close_command` is configured, closing a buffer continues to use the default buffer deletion action.
