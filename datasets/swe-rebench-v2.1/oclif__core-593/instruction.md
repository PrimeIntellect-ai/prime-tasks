Return result in Main.ts run function
**Describe the bug**

Everywhere else throughout the call stack for Commands, the result of a command is propagated upwards - [except here in main.ts](https://github.com/oclif/core/blob/main/src/main.ts#L77). As a result, for those looking to interact with the result of commands (short of commands that offer direct support for the filesystem, which works in the interim as an indirect way to get access to command results), we're left hanging - we can properly await a command, but can't properly resolve the result of a command.

**Expected behavior**

It would be great to update the line from:

```ts
await config.runCommand(id, argvSlice, cmd);
```

to:

```ts
[HIDDEN]
```

So that we can interact with the result of a command without having to write to the file-system as an intermediary.

**Environment (please complete the following information):**
 - applicable on any OS
 - applicable as of `@oclif/core` version `1.24.0`

### Additional contract requirements

- When `Main.run` executes a command, its returned promise must resolve to that command’s result so callers can inspect it directly.
