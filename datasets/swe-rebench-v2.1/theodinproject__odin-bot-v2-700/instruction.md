Chore: Use flags for ephemeral messages instead of options
### Checks

- [x] I have thoroughly read and understand [The Odin Project Contributing Guide](https://github.com/TheOdinProject/.github/blob/main/CONTRIBUTING.md)
- [x] The title of this issue follows the `command name: brief description of request` format, e.g. `/help: add optional @user parameter`

### Do you want to be assigned to this issue?

- [ ] I would like to be assigned this issue to work on it

### Description of the Feature Request

Noticed this in the console. We should probably update the codebase.

> (node:49414) Warning: Supplying "ephemeral" for interaction response options is deprecated. Utilize flags instead.

### Acceptance Criteria

- All instances where "ephemeral" is used as an option are updated to use flags instead
- Ensure all existing tests still pass


### Additional information

I haven't looked into this yet. This is more of a `TODO`.

### Additional contract requirements

- The replacement is the `MessageFlags.Ephemeral` flag from `discord.js` (numeric value `64`), supplied as the `flags` property of the interaction reply options.
- The deprecated `ephemeral` option must no longer be supplied in those reply options.
