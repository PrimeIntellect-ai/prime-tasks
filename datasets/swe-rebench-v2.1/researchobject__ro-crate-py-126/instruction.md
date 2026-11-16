Allow root dataset to have more than one type
Fails if root dataset has an array as a value for @type

eg. @type = ['Dataset', 'RepositoryCollection']

Note: @ptsefton says: Can we always code defensively, please.


https://github.com/ResearchObject/ro-crate-py/blob/9c010654dce2b8cd9ca4e99dd73885439885e4fc/rocrate/rocrate.py#L154

### Additional contract requirements

- When rejecting a root entity whose `@type` is `Thing`, raise a `ValueError` with a message containing `must have`.
