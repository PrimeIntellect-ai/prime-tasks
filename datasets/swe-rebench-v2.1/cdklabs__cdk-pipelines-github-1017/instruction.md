Allow access to `permissions` property of GitHubActionStep's in pre/post
#304 is a great feature, however, it doesn't not provide a surface to control the `permissions` property emitted for the job. This means that the job emitted cannot be provided with the `id-token: write` permission and cannot authenticate with AWS using the GitHub identity provider.

Either access to the `permissions` property of the `GitHubActionStep` or the ability to pass `id-token: write` as a boolean would make `GitHubActionStep`'s much more useful in pre/post deploy steps.

Taking a look over #304, I think the change should be fairly trivial? Provided I have time, I may be able to open a PR.

### Additional contract requirements

- `GitHubActionStep` accepts an optional `permissions` property in its props, of type `JobPermissions`. This property is the surface for controlling the permissions emitted for the step's job.
- When `permissions` is omitted, the emitted job uses the default permission set `{ contents: write }`.
- When `permissions` is provided, the emitted job uses exactly the supplied mapping. For example, `{ idToken: JobPermission.WRITE, contents: JobPermission.WRITE }` emits `id-token: write` followed by `contents: write`.
- Custom permissions apply to `GitHubActionStep`s used as both pre and post steps.
