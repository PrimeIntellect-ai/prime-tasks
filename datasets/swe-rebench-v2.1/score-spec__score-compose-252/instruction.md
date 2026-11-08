[feature request] Add a new `score-compose provisioners list` command
Add a new `score-compose provisioners list` command generating in the output this table or a more advanced/detailed version with `-o json`: https://docs.score.dev/docs/score-implementation/score-compose/resources-provisioners/.

- It's not something in `score-go` as it's specific to each implementation.
- This should list the overriden `provisioners` imported via the `score-compose init --provisioners` command

### Additional contract requirements

- The command is `score-compose provisioners list`. It reads the provisioners from the active `.score-compose` state directory (created by `score-compose init`), so provisioners imported with `score-compose init --provisioners <file>` are included in the listing.
- The output format is selected with the `--format` flag (shorthand `-f`), which defaults to `table`. Passing `json` (for example `-f json` or `--format json`) renders the JSON array; any other value renders the human-readable table.
