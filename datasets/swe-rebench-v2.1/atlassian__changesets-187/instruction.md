Feature Request: add `--empty` flag to create an empty changeset
G'day.

We're looking at adding enforcement to PRs that will mean that all PRs must have a changeset. To make this cleaner/more consistent, it would be good if we could create empty changesets to signify "I have *deliberately chosen* to not release a package in this PR.

Happy to make a PR for v1.

### Additional contract requirements

- The CLI accepts `--empty` both as `changesets --empty` and `changesets add --empty`. Either invocation creates a changeset without requiring the normal interactive release choices, with no package releases and an empty summary.
- An empty changeset file is accepted by the existing changeset parsing and reading functionality and is exposed as having no releases and an empty summary.
