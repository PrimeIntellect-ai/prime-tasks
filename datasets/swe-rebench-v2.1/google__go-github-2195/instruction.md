IssuesService.Edit cannot clear an issue's milestone
Much like #181 I fail to see how to use go-github to clear an issue's milestone. The API requires the milestone be to set to `null` in the request so that it is cleared, but that is not possible since the field uses `omitempty`.

Not sure what the right solution would be, perhaps a standalone method for clearing milestones?

### Additional contract requirements

- Callers need a public `IssuesService.RemoveMilestone` operation that accepts a context, repository owner, repository name, and issue number; it may accept additional options.
- The PATCH request body must be a JSON object that sets the `milestone` field to
  `null` (i.e. `{"milestone":null}`), so that the issue's milestone is cleared.
