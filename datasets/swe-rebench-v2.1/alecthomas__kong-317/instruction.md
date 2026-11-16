Kong allows multiple sub-commands to have the same name
If I specify name explicitly for sub-command structs, I can use the same one and at least `--help` does not complain but happily print out a list of sub-commands with same name. I think this should fail for ease of debugging.

### Additional contract requirements

Two subcommands with the same effective name under the same parent must be rejected, including when the names are explicitly assigned; the configuration must be rejected before `--help` lists the duplicates as separate commands. The same effective name is allowed at distinct command paths when the commands are not siblings.
