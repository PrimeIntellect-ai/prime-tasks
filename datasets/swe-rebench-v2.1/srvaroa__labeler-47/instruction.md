Option to append to existing Labels
Please provide an option to append labels to the already existing labels on a PR.
Currently it removes all existing labels from a PR and applies those which meet the conditions. But, there are use cases where people want to manually add labels to the PR and maintain it.

### Additional contract requirements

- The configuration type `LabelerConfigV1` in package `pkg` (module `github.com/srvaroa/labeler/pkg`) exposes a public boolean field `AppendOnly`.
- When `AppendOnly` is true, a label whose rule matches is added to the pull request, and labels already present on the pull request are never removed, even when a configured rule for them does not match.
- When `AppendOnly` is false or unset, the pull request's labels are added and removed so that they exactly match the set of labels whose rules match.
