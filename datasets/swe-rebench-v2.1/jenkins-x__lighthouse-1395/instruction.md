Feature request: Share aliases between repositories
As a fall back for aliases missing from the OWNER_ALIASES file I propose support for reading OWNER_ALIASES files from other repositories.

This is practical when teams have responsibility for several repositories.

### Additional contract requirements

The OWNERS_ALIASES file may contain a `foreignAliases` list in addition to the local `aliases` map. Each `foreignAliases` entry is a mapping with the following keys:

- `name` (required): the name of the repository whose OWNERS_ALIASES file should be imported.
- `org` (optional): the organization that owns the referenced repository; when omitted it defaults to the organization of the primary repository.
- `ref` (optional): the git reference (branch, tag, or commit) to read the referenced file from; when omitted it defaults to `HEAD`.

Aliases imported from foreign repositories are merged with the aliases defined locally: when the same alias appears in several sources, the members are combined. Foreign files are processed recursively, so an imported OWNERS_ALIASES file may itself declare `foreignAliases` entries, which are imported as well.
