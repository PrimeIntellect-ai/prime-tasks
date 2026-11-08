[CLI] `check-parse` command (or another command) should check parsing of entity data and schemas, not just policies
### Category

Other

### Describe the feature you'd like to request

Currently, the CLI `check-parse` command only checks the parsing of policies.

To check the parsing of entity data or schemas, you have to use other commands -- for instance `authorize` for entity data, or `validate` for schemas.  But this is inconvenient, as you also have to provide other inputs for those commands, like policies.  We don't have a dedicated way to check the parsing of entity data or schemas without also having to provide unnecessary inputs.

### Describe alternatives you've considered

We could have separate commands `check-policies-parse`, `check-entities-parse`, `check-schema-parse`; or (my preference) just have a single `check-parse` which checks that any or all of these parse.  `check-parse` could check the parsing of any or all of these in a single call -- e.g., if you pass just schema, it checks the parsing of the schema, or if you pass both entities and policies, it checks the parsing of the entities and policies; etc.

### Additional context

_No response_

### Is this something that you'd be interested in working on?

- [ ] 👋 I may be able to implement this feature request
- [ ] ⚠️ This feature might incur a breaking change

### Additional contract requirements

- The `check-parse` command accepts `--policies FILE`, `--schema FILE` and `--entities FILE`, in any combination, including each one alone.
- Each supplied input is parsed. The command succeeds only when every supplied input parses, and it fails (non-zero exit status) when any supplied input does not parse, even if the other inputs parse.
