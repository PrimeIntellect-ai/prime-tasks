commands: we should make builder, handler, description, command optional
It's not the case that we always wand a builder function for a command, I propose that we make each of these parameters optional.

### Additional contract requirements

When a command is registered from a module-style object that has no string `command` field, its command name is the basename of the module's filename, without the file extension. The command must then be available under that name for normal command matching and invocation.
