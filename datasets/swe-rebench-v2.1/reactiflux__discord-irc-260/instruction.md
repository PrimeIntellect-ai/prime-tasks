Commands to IRC from Discord without announcement
Ok, so as its currently set by default, command characters (such as !) that are set in the config are prefixed by a line saying Command sent from Discord by name:
I know it the current version, it can be changed to something else, but is there a way to omit that entirely, just have it send the command through?

### Additional contract requirements

- The announcement prelude is configured through the existing `format.commandPrelude` option.
- Setting `format.commandPrelude` to a falsy value (for example `null` or an empty string) omits the prelude entirely, so a command originating in Discord is sent to IRC on its own with no announcement line.
