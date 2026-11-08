Support parsing tags without "v" prefix
## Description

As from https://github.com/relekang/python-semantic-release/blob/master/semantic_release/vcs_helpers.py#L72 it seems the tool expects tags to be named like "v1.2.3".

However I use tags like "1.2.3" and I don't see reasons to add "v". I would expect the tool should be smart enough to find the version out of such tags as well


## Use cases

Repos having `1.2.3` as tags.

## Possible implementation

[HIDDEN]

### Additional contract requirements

- A repository whose latest version tag is named with a bare numeric version such as `1.2.3` (no `v` prefix) must be recognized: the tool's latest-version lookup reports `1.2.3`.
- Existing tags named like `v1.2.3` must keep being recognized: the latest-version lookup reports `1.2.3` for them.
- When the repository has both styles of tag, the most recently created version tag determines the reported version, whichever style it uses.
